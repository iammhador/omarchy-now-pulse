// Now Pulse service: the one shared brain behind every bar instance.
//
// The shell creates a single service, while a bar widget exists per monitor.
// It watches every MPRIS player (browsers, Spotify, mpv, VLC, ...), decides
// which one the bar shows, and owns everything with a side effect: control
// calls, the position tick, cover color sampling and "pause the others".
// Widgets only render this state and call its functions.

import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import qs.Commons as Commons
import "Model.js" as Model

Item {
  id: svc

  // Injected by the shell.
  property var shell: null
  property var manifest: null

  // ---------------------------------------------------------------- config
  // Pushed by the bar widgets, which share one settings entry.

  property bool skipSpotify: false
  property bool pauseOthers: false
  property bool coverColors: true
  property bool pillProgress: true

  function configure(c) {
    skipSpotify = c.skipSpotify === true
    pauseOthers = c.pauseOthers === true
    coverColors = c.coverColors !== false
    pillProgress = c.pillProgress !== false
  }

  readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/now-pulse"

  // ---------------------------------------------------------------- players

  // Every source worth showing, in the order MPRIS lists them.
  readonly property var players: Model.filterPlayers(Mpris.players.values, { skipSpotify: skipSpotify })
  readonly property int count: players.length

  // key -> ms when it last (really) started playing, and when it stopped.
  // Replaced, not mutated, so bindings notice.
  property var lastPlayed: ({})
  property var lastStopped: ({})
  // The source picked in the card. Cleared when a different one takes over.
  property string pinned: ""
  // While a card is open the bar never switches under the pointer (a seek
  // drag must not land on another player). Set by the widget.
  property string frozenKey: ""

  readonly property var player: Model.selectActive(players, frozenKey !== "" ? frozenKey : pinned, lastPlayed)
  readonly property string playerKey: Model.key(player)

  // A source takes over only after playing this long without a break, so
  // hover previews, ads and short blips don't steal the bar.
  readonly property int takeoverMs: 2000

  function _with(map, k, v) {
    var next = {}
    for (var key in map) next[key] = map[key]
    next[k] = v
    return next
  }

  function notePlaying(p) {
    if (!p || Model.isProxy(p)) return
    var k = Model.key(p)
    lastPlayed = _with(lastPlayed, k, Date.now())
    if (pinned !== "" && pinned !== k) pinned = ""
    if (pauseOthers) pauseAllBut(k)
  }
  function noteStopped(p) {
    if (p && !Model.isProxy(p)) lastStopped = _with(lastStopped, Model.key(p), Date.now())
  }
  function freeze(open) {
    frozenKey = open ? playerKey : ""
  }

  function pauseAllBut(k) {
    var all = Mpris.players.values
    for (var i = 0; i < all.length; i++) {
      var o = all[i]
      if (!o || Model.isProxy(o) || Model.key(o) === k) continue
      if (o.isPlaying && o.canPause) o.pause()
    }
  }

  // Watch every player's play state (including ones filtered out, so their
  // history is right the moment they get a title).
  Instantiator {
    model: Mpris.players
    delegate: Item {
      id: watch
      required property var modelData
      readonly property bool playing: !!modelData && modelData.isPlaying
      onPlayingChanged: {
        if (playing) takeover.restart()
        else { takeover.stop(); svc.noteStopped(modelData) }
      }
      // Already playing when the shell starts: no wait.
      Component.onCompleted: if (playing) svc.notePlaying(modelData)
      Timer {
        id: takeover
        interval: svc.takeoverMs
        onTriggered: if (watch.playing) svc.notePlaying(watch.modelData)
      }
    }
  }

  function pin(k) {
    pinned = k
    if (frozenKey !== "") frozenKey = k
    if (player) player.positionChanged()
  }
  function cycleSource(dir) {
    if (count > 1) pin(Model.cycleKey(players, playerKey, dir))
  }

  // ---------------------------------------------------------------- now playing

  readonly property bool running: player !== null
  readonly property bool playing: running && player.isPlaying
  readonly property string title: running ? String(player.trackTitle || "") : ""
  readonly property string artist: running ? String(player.trackArtist || "") : ""
  readonly property string album: running ? String(player.trackAlbum || "") : ""
  readonly property string artUrl: running ? String(player.trackArtUrl || "") : ""
  readonly property string trackKey: playerKey + "\u0001" + title + "\u0001" + artist
  readonly property real duration: running && player.lengthSupported ? Math.max(0, player.length) : 0
  readonly property real position: running && player.positionSupported ? Model.clamp(player.position, 0, duration || 1e9) : 0
  readonly property real progress: duration > 0 ? position / duration : 0
  readonly property bool volumeSupported: running && player.volumeSupported
  readonly property real volume: volumeSupported ? player.volume : 0

  readonly property string appName: Model.appName(player)
  readonly property string appGlyph: Model.appGlyph(player)
  readonly property string site: siteFor(player)
  readonly property string siteGlyph: Model.siteGlyph(site)
  // What to call it when the player gives no title.
  readonly property string displayTitle: title !== "" ? title : (site || appName)
  // "YouTube · Zen", or just the app.
  readonly property string sourceLabel: site !== "" && site !== appName ? site + "  ·  " + appName : appName
  readonly property bool live: running && duration <= 0
  readonly property bool browser: Model.isBrowser(player)

  // The site a player is on: from its URL, else from its window's title
  // (Brave and Chrome send no URL, but end titles with "- YouTube - Brave").
  function siteFor(p) {
    if (!p) return ""
    var url = p.metadata ? p.metadata["xesam:url"] : ""
    var s = Model.siteName(url)
    if (s !== "") return s
    var w = windowFor(p)
    return w ? Model.siteFromTitle(w.title) : ""
  }
  function labelFor(p) { return siteFor(p) || Model.appName(p) }

  // The window showing a player, or null when it can't be told for sure.
  function windowFor(p) {
    if (!p || Model.isAudioApp(p)) return null
    var all = ToplevelManager.toplevels.values
    var list = []
    for (var i = 0; i < all.length; i++) list.push({ appId: all[i].appId, title: all[i].title })
    var idx = Model.pickWindow(list, Model.desktopId(p), String(p.trackTitle || ""))
    return idx >= 0 ? all[idx] : null
  }

  // When a source paused (ms ago), for "Paused · 2 h ago".
  function pausedFor(p) {
    var t = p ? lastStopped[Model.key(p)] : 0
    return t ? Date.now() - t : 0
  }

  // The app's real icon from its .desktop entry, "" when there isn't one.
  function iconFor(p) {
    var id = Model.desktopId(p)
    if (id === "") return ""
    var entry = DesktopEntries.heuristicLookup(id)
    var name = entry && entry.icon ? entry.icon : id
    return Quickshell.iconPath(name, true) || ""
  }
  readonly property string appIcon: running ? iconFor(player) : ""

  // ---------------------------------------------------------------- video
  // The window showing the current player's video, for the card's live
  // mirror: a Picture-in-Picture window, else the window whose active tab is
  // this track, else any window of the app. Null when there's none.

  readonly property var videoWindow: running ? windowFor(player) : null
  readonly property bool hasVideo: videoWindow !== null
  // Could have video, but its window can't be told apart (generic title,
  // or several windows): the switch shows, disabled, saying why.
  readonly property bool videoPossible: running && !Model.isAudioApp(player) && (browser || hasVideo)
  // The video plays in a background tab: the mirror would show another page.
  readonly property bool videoTabHidden: hasVideo && !Model.showsTrack(videoWindow.title, title)
  readonly property bool canShowTab: running && player.canRaise

  // Bring the playing tab to the front of its window (MPRIS Raise selects it
  // in Firefox / Zen), then hop back to the workspace you were on.
  function showVideoTab() {
    if (!canShowTab || tabProc.running) return
    tabProc.command = ["sh", "-c",
      'ws=$(hyprctl activeworkspace -j | jq -r .id)\n'
      + 'busctl --user call "$1" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2 Raise || exit 1\n'
      + 'sleep 0.35\n'
      + '[ -n "$ws" ] || exit 0\n'
      + 'r=$(hyprctl dispatch "hl.dsp.focus({ workspace = $ws })" 2>&1)\n'
      + '[ "$r" = ok ] || hyprctl dispatch workspace "$ws" >/dev/null',
      "sh", String(player.dbusName)]
    tabProc.running = true
  }
  Process { id: tabProc }

  // Video framing (zoom, pan) per site (YouTube and Instagram in the same
  // browser frame differently), else per app; for this session.
  property var videoViews: ({})
  readonly property string viewKey: site !== "" ? site : Model.desktopId(player)
  readonly property var videoView: videoViews[viewKey] || ({ zoom: 1, fx: 0, fy: 0 })
  function saveVideoView(view) { videoViews = _with(videoViews, viewKey, view) }

  // ---------------------------------------------------------------- controls

  function playPause() { if (running && player.canTogglePlaying) player.togglePlaying() }
  function next() { if (running && player.canGoNext) player.next() }
  function previous() {
    if (!running) return
    // Like most players: restart the track unless we're at its very start.
    if (position > 4 && player.canSeek && duration > 0) seekTo(0)
    else if (player.canGoPrevious) player.previous()
    else if (player.canSeek && duration > 0) seekTo(0)
  }
  function seekTo(seconds) {
    if (running && player.canSeek && duration > 0) player.position = Model.clamp(seconds, 0, duration - 0.5)
  }
  function setVolume(v) {
    if (volumeSupported) player.volume = Model.clamp(v, 0, 1)
  }
  function toggleShuffle() { if (running && player.shuffleSupported) player.shuffle = !player.shuffle }
  function cycleRepeat() {
    if (!running || !player.loopSupported) return
    if (player.loopState === MprisLoopState.None) player.loopState = MprisLoopState.Playlist
    else if (player.loopState === MprisLoopState.Playlist) player.loopState = MprisLoopState.Track
    else player.loopState = MprisLoopState.None
  }
  function playPauseKey(k) {
    for (var i = 0; i < players.length; i++)
      if (Model.key(players[i]) === k && players[i].canTogglePlaying) players[i].togglePlaying()
  }

  // Bring the app forward: the exact window when it's known, else Hyprland
  // focus by window class, then MPRIS Raise.
  function raise() {
    if (!running) return
    if (videoWindow) { videoWindow.activate(); return }
    var cls = Model.windowClass(player)
    if (cls === "") { if (player.canRaise) player.raise(); return }
    focusProc.running = false
    focusProc.command = ["sh", "-c",
      'r=$(hyprctl dispatch "hl.dsp.focus({ window = \\"$1\\" })" 2>&1)\n'
      + '[ "$r" = ok ] && exit 0\n'
      + 'r=$(hyprctl dispatch focuswindow "$1" 2>&1)\n'
      + '[ "$r" = ok ]', "sh", cls]
    focusProc.running = true
  }

  Process {
    id: focusProc
    onExited: function(code) { if (code !== 0 && svc.running && svc.player.canRaise) svc.player.raise() }
  }

  // ---------------------------------------------------------------- position
  // MPRIS position is interpolated on read; nudging the signal refreshes
  // bindings. Fast while a card is open, slow for the bar's progress, and
  // not at all otherwise.

  property int openCards: 0
  function cardOpened(open) {
    openCards = Math.max(0, openCards + (open ? 1 : -1))
    if (open && running) player.positionChanged()
  }

  readonly property int tickInterval: openCards > 0 ? 250 : (pillProgress ? 1000 : 0)

  Timer {
    interval: Math.max(250, svc.tickInterval)
    repeat: true
    running: svc.playing && svc.tickInterval > 0
    onTriggered: svc.player.positionChanged()
  }

  // ---------------------------------------------------------------- colors
  // Browsers and most players hand over a local file; ColorQuantizer only
  // reads local files, so fetch web covers (Spotify's) once into a small
  // cache, pruned after a week.

  readonly property bool darkTheme: Commons.Color.background.hslLightness < 0.5
  property color coverA: Commons.Color.accent
  property color coverB: Commons.Color.accent
  property bool coverOk: false
  readonly property color accent: coverColors && coverOk && hasArt ? coverA : Commons.Color.accent
  readonly property color accent2: coverColors && coverOk && hasArt ? coverB : Commons.Color.accent

  // Real cover art, or nothing / a site or app logo standing in for it (a
  // small square from a browser, or an icon file). Logos never become the
  // hero or the card's colors.
  readonly property bool artLogo: artUrl !== "" && (/favicon|\/icons?\//i.test(artUrl)
    || (browser && artProbe.status === Image.Ready
        && artProbe.implicitWidth <= 256 && Math.abs(artProbe.implicitWidth - artProbe.implicitHeight) <= 8))
  readonly property bool hasArt: artUrl !== "" && !artLogo && artProbe.status !== Image.Error
  Image {
    id: artProbe
    visible: false
    source: svc.artUrl
    asynchronous: true
    cache: false
  }
  property string artFile: ""

  function fetchArt() {
    artFetch.running = false
    if (!coverColors || artUrl === "") { artFile = ""; coverOk = false; return }
    if (artUrl.indexOf("file://") === 0) { artFile = decodeURIComponent(artUrl.substring(7)); return }
    if (!/^https?:\/\//i.test(artUrl)) { artFile = ""; coverOk = false; return }
    artFetch.target = cacheDir + "/" + Qt.md5(artUrl) + ".img"
    artFetch.command = ["sh", "-c",
      'mkdir -p "$1" && find "$1" -name "*.img" -mtime +7 -delete; [ -s "$2" ] || curl -sfL --max-time 10 -o "$2" "$3"',
      "sh", cacheDir, artFetch.target, artUrl]
    artFetch.running = true
  }

  Process {
    id: artFetch
    property string target: ""
    onExited: function(code) { if (code === 0) svc.artFile = target }
  }

  function sampleColors() {
    var p = Model.accentPair(quantizer.colors, darkTheme, Qt)
    coverOk = p !== null
    if (p) { coverA = p.a; coverB = p.b }
  }

  ColorQuantizer {
    id: quantizer
    source: svc.artFile !== "" ? "file://" + svc.artFile : ""
    depth: 3
    rescaleSize: 64
    onColorsChanged: svc.sampleColors()
  }

  onArtUrlChanged: fetchArt()
  onCoverColorsChanged: fetchArt()
  onDarkThemeChanged: sampleColors()
  Component.onCompleted: fetchArt()
}
