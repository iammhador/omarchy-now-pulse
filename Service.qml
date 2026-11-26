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
import Quickshell.Hyprland
import qs.Commons
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
  property bool trackToast: true
  property int toastSeconds: 4
  property string barPosition: "top"
  property string fontFamily: Style.font.family

  function configure(c) {
    skipSpotify = c.skipSpotify === true
    pauseOthers = c.pauseOthers === true
    coverColors = c.coverColors !== false
    pillProgress = c.pillProgress !== false
    trackToast = c.trackToast !== false
    toastSeconds = Math.max(2, Math.min(15, Number(c.toastSeconds) || 4))
    if (c.barPosition) barPosition = String(c.barPosition)
    if (c.fontFamily) fontFamily = String(c.fontFamily)
  }

  readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/now-pulse"

  // ---------------------------------------------------------------- players

  // Every source worth showing, in the order MPRIS lists them.
  readonly property var players: Model.filterPlayers(Mpris.players.values, { skipSpotify: skipSpotify, keep: holdKey, demoOnly: demoOnly })
  // Set over IPC (`demo true`) for screenshots: real sources stay hidden.
  property bool demoOnly: false

  // Between two tracks a source reports "Stopped" with no title for a while
  // (YouTube's autoplay countdown is ~8 s, a click to another video ~0.5 s).
  // The last source with a title is held, with its last track, until it
  // has been blank this long, so the bar doesn't blink and the card stays open.
  readonly property int holdMs: 12000
  property string holdKey: ""
  property var held: ({ title: "", artist: "", album: "", artUrl: "" })
  Timer {
    id: holdTimer
    interval: svc.holdMs
    onTriggered: svc.holdKey = ""
  }
  function noteTitle(p, titled) {
    var k = Model.key(p)
    if (titled) {
      if (k === holdKey) holdTimer.stop()
    } else if (k === holdKey) holdTimer.restart()
  }
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
      readonly property bool titled: !!modelData && String(modelData.trackTitle || "").trim() !== ""
      onTitledChanged: svc.noteTitle(modelData, titled)
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
  readonly property bool playing: running && !!player && player.isPlaying
  readonly property string rawTitle: running && !!player ? String(player.trackTitle || "").trim() : ""
  // Riding out a gap between tracks: show the last one.
  readonly property bool holding: running && rawTitle === "" && playerKey === holdKey && held.title !== ""
  readonly property string title: holding ? held.title : rawTitle
  readonly property string artist: holding ? held.artist : (running && !!player ? String(player.trackArtist || "") : "")
  readonly property string album: holding ? held.album : (running && !!player ? String(player.trackAlbum || "") : "")
  readonly property string artUrl: holding ? held.artUrl : (running && !!player ? String(player.trackArtUrl || "") : "")
  // Remember the current track, keyed by its source, for the gap after it.
  // Read the key from the player itself: playerKey may not have caught up yet.
  function captureHold() {
    if (rawTitle === "" || !player) return
    // players depends on holdKey: set it after this evaluation, not inside it.
    var k = Model.key(player)
    if (k !== holdKey) Qt.callLater(function() { if (svc.player && Model.key(svc.player) === k) svc.holdKey = k })
    holdTimer.stop()
    held = { title: rawTitle, artist: String(player.trackArtist || ""), album: String(player.trackAlbum || ""),
             artUrl: String(player.trackArtUrl || "") }
  }
  onRawTitleChanged: captureHold()
  onPlayerChanged: captureHold()
  onRunningChanged: if (!running) { holdTimer.stop(); holdKey = ""; held = { title: "", artist: "", album: "", artUrl: "" } }
  readonly property string trackKey: playerKey + "\u0001" + title + "\u0001" + artist
  readonly property real duration: running && !!player && player.lengthSupported ? Math.max(0, player.length) : 0
  readonly property real position: running && !!player && player.positionSupported ? Model.clamp(player.position, 0, duration || 1e9) : 0
  readonly property real progress: duration > 0 ? position / duration : 0
  readonly property bool volumeSupported: running && !!player && player.volumeSupported
  readonly property real volume: volumeSupported ? player.volume : 0

  readonly property string appName: Model.appName(player)
  readonly property string appGlyph: Model.appGlyph(player)
  readonly property string site: siteFor(player)
  readonly property string siteGlyph: Model.siteGlyph(site)
  // What to call it when the player gives no title.
  readonly property string displayTitle: title !== "" ? title : (site || appName)
  // "YouTube · Zen", or just the app.
  readonly property string sourceLabel: site !== "" && site !== appName ? site + "  ·  " + appName : appName
  // No timeline: either a real live stream, or a player that doesn't share
  // one (Zen / Firefox never send a length). Only call it LIVE when it looks
  // like one; otherwise just show no seek bar.
  readonly property bool timeless: running && duration <= 0
  readonly property bool live: timeless && Model.looksLive(title, site)
  readonly property bool browser: Model.isBrowser(player)

  // The site a player is on: from its URL, else from its window's title
  // (Brave and Chrome send no URL, but end titles with "- YouTube - Brave").
  function siteFor(p) {
    if (!p) return ""
    var url = p.metadata ? p.metadata["xesam:url"] : ""
    var s = Model.siteName(url)
    if (s !== "") return s
    var track = String(p.trackTitle || "")
    s = Model.siteFromTrack(track)
    if (s !== "") return s
    var w = windowFor(p)
    if (w) s = Model.siteFromTitle(w.title) || Model.siteGuess(w.title, track, String(p.trackArtist || ""))
    // Brave / Chrome only name the site through the active tab's title: keep
    // what was learned for this source while its tab is in the background
    // or between tracks.
    var k = Model.key(p)
    var memo = siteMemo[k]
    if (s !== "") {
      if (!memo || memo.site !== s || memo.track !== track) _remember(k, { site: s, track: track })
      return s
    }
    // Only for the same track (or the blank gap after it): another tab may
    // have started something else on another site.
    return memo && (track === "" || memo.track === track) ? memo.site : ""
  }
  // key -> { site, track } last seen. Written outside the binding reading it.
  property var siteMemo: ({})
  function _remember(k, v) { Qt.callLater(function() { svc.siteMemo = svc._with(svc.siteMemo, k, v) }) }
  function labelFor(p) { return siteFor(p) || Model.appName(p) }

  // The window showing a player, or null when it can't be told for sure.
  function windowFor(p) {
    if (!p || Model.isAudioApp(p)) return null
    var want = Model.desktopId(p).toLowerCase()
    var sameApp = 0
    for (var j = 0; j < players.length; j++) {
      if (Model.desktopId(players[j]).toLowerCase() === want) sameApp++
    }
    var all = ToplevelManager.toplevels.values
    var list = []
    for (var i = 0; i < all.length; i++) list.push({ appId: all[i].appId, title: all[i].title })
    var idx = Model.pickWindow(list, want, String(p.trackTitle || ""), sameApp)
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
  readonly property bool canShowTab: running && !!player && player.canRaise

  // Bring the playing tab to the front of its window (MPRIS Raise selects it
  // in Firefox / Zen), then hop back to the workspace you were on.
  function showVideoTab() {
    if (!canShowTab || !player || tabProc.running) return
    var bus = String(player.dbusName || "")
    if (!/^org\.mpris\.MediaPlayer2\.[A-Za-z0-9_.-]+$/.test(bus)) return
    tabProc.command = ["sh", "-c",
      'ws=$(hyprctl activeworkspace -j | jq -r .id 2>/dev/null)\n'
      + 'busctl --user call "$1" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2 Raise || exit 1\n'
      + 'sleep 0.35\n'
      + 'case "$ws" in ""|null) exit 0;; esac\n'
      + 'r=$(hyprctl dispatch "hl.dsp.focus({ workspace = $ws })" 2>&1)\n'
      + '[ "$r" = ok ] || hyprctl dispatch workspace "$ws" >/dev/null',
      "sh", bus]
    tabProc.running = true
  }
  Process { id: tabProc }

  // Video framing (zoom, pan) per site (YouTube and Instagram in the same
  // browser frame differently), else per app; for this session.
  property var videoViews: ({})
  readonly property string viewKey: site !== "" ? site : Model.desktopId(player)
  readonly property var videoView: videoViews[viewKey] || ({ zoom: 1, fx: 0, fy: 0 })
  function saveVideoView(view) { if (viewKey !== "") videoViews = _with(videoViews, viewKey, view) }

  // ---------------------------------------------------------------- controls

  function playPause() { if (running && !!player && player.canTogglePlaying) player.togglePlaying() }
  function next() { if (running && !!player && player.canGoNext) player.next() }
  function previous() {
    if (!running) return
    // Like most players: restart the track unless we're at its very start.
    if (position > 4 && player.canSeek && duration > 0) seekTo(0)
    else if (player.canGoPrevious) player.previous()
    else if (player.canSeek && duration > 0) seekTo(0)
  }
  function seekTo(seconds) {
    if (running && !!player && player.canSeek && duration > 0) player.position = Model.clamp(seconds, 0, duration - 0.5)
  }
  function setVolume(v) {
    if (volumeSupported) player.volume = Model.clamp(v, 0, 1)
  }
  function toggleShuffle() { if (running && !!player && player.shuffleSupported) player.shuffle = !player.shuffle }
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
    onExited: function(code) { if (code !== 0 && svc.running && svc.player && svc.player.canRaise) svc.player.raise() }
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
    onTriggered: if (svc.player) svc.player.positionChanged()
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
  property int artSeq: 0

  function fetchArt() {
    artFetch.running = false
    artSeq++
    if (!coverColors || artUrl === "") { artFile = ""; coverOk = false; return }
    if (artUrl.indexOf("file://") === 0) {
      try {
        artFile = decodeURIComponent(artUrl.replace(/^file:\/\/(?:localhost)?/i, ""))
      } catch (e) {
        artFile = ""; coverOk = false
      }
      return
    }
    if (!/^https?:\/\//i.test(artUrl)) { artFile = ""; coverOk = false; return }
    artFile = ""; coverOk = false
    var target = cacheDir + "/" + Qt.md5(artUrl) + ".img"
    artFetch.pendingSeq = artSeq
    artFetch.pendingTarget = target
    artFetch.command = ["sh", "-c",
      'mkdir -p -m 700 "$1" && find "$1" -maxdepth 1 -type f -name "*.img" -mtime +7 -delete\n'
      + 'if [ -s "$2" ] && [ ! -L "$2" ]; then exit 0; fi\n'
      + 'tmp="$2.part.$$"\n'
      + 'trap \'rm -f "$tmp"\' EXIT\n'
      + 'curl -sfL --proto "=http,https" --proto-redir "=http,https" --max-filesize 10485760 --max-time 10 -o "$tmp" -- "$3" && mv -f "$tmp" "$2"',
      "sh", cacheDir, target, artUrl]
    artFetch.running = true
  }

  Process {
    id: artFetch
    property string pendingTarget: ""
    property int pendingSeq: 0
    onExited: function(code) { if (code === 0 && pendingSeq === svc.artSeq) svc.artFile = pendingTarget }
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


  // ---------------------------------------------------------------- pop-up
  // A small card under the bar when a new track starts. Not for the first
  // track after the shell starts, a repeat of the one just shown, a source
  // that isn't playing, while a card is open, during Do Not Disturb, over a
  // fullscreen window, or when you're looking at the playing app already.

  signal cardRequested()

  property string toastShownKey: ""
  property var toastData: ({})
  property bool toastUp: false
  property bool started: false
  Timer { interval: 3000; running: true; onTriggered: svc.started = true }

  // Omarchy's notification quiet state: {"dnd": true}.
  property bool doNotDisturb: false
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/notifications/quiet.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try { svc.doNotDisturb = JSON.parse(text()).dnd === true } catch (e) { svc.doNotDisturb = false }
    }
    onLoadFailed: svc.doNotDisturb = false
  }

  // Title + artist, not the player: the same song from another source is
  // not news.
  readonly property string songKey: title + "\u0001" + artist
  onSongKeyChanged: if (title !== "") toastDelay.restart()
  onPlayingChanged: if (playing && title !== "" && songKey !== toastShownKey) toastDelay.restart()

  // Wait for the metadata to settle (players send title, then artist, then
  // art) and for the source to really be playing.
  Timer {
    id: toastDelay
    interval: 1200
    onTriggered: svc.maybeToast()
  }

  function lookingAtPlayer() {
    var w = ToplevelManager.activeToplevel
    if (!w || !running) return false
    var id = String(w.appId || "").toLowerCase()
    var want = Model.desktopId(player).toLowerCase()
    if (id === "" || want === "") return false
    // Same app; for browsers only when the playing tab is the one in front.
    if (id !== want && id.replace(/-browser$/, "") !== want.replace(/-browser$/, "")) return false
    return !browser || Model.showsTrack(w.title, title)
  }
  function fullscreenNow() {
    var ws = Hyprland.focusedWorkspace
    return !!ws && ws.hasFullscreen === true
  }

  // Why the last track change did or didn't pop up (for `status`).
  property string toastReason: ""
  function maybeToast() {
    if (!trackToast) { toastReason = "off"; return }
    if (!started || !running || !playing || holding || title === "") { toastReason = "not playing yet"; return }
    if (songKey === toastShownKey) { toastReason = "same song"; return }
    toastShownKey = songKey
    if (openCards > 0) { toastReason = "card open"; return }
    if (doNotDisturb) { toastReason = "do not disturb"; return }
    if (fullscreenNow()) { toastReason = "fullscreen"; return }
    if (lookingAtPlayer()) { toastReason = "looking at the player"; return }
    toastReason = "shown"
    showToast()
  }
  function showToast() {
    if (!running) return
    toastData = {
      title: displayTitle, artist: artist, source: sourceLabel,
      glyph: siteGlyph || appGlyph, art: artUrl, hasArt: hasArt,
      canNext: !!player && player.canGoNext
    }
    toastUp = true
    Qt.callLater(function() { if (svc.toastItem) svc.toastItem.show() })
  }
  function hideToast() { if (toastItem) toastItem.hide() }
  property var toastItem: null

  PanelWindow {
    id: toastWindow
    visible: svc.toastUp
    screen: {
      var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
      var list = Quickshell.screens
      for (var i = 0; i < list.length; i++) if (list[i].name === name) return list[i]
      return list.length ? list[0] : null
    }
    anchors.top: svc.barPosition !== "bottom"
    anchors.bottom: svc.barPosition === "bottom"
    margins.top: Style.space(8)
    margins.bottom: Style.space(8)
    implicitWidth: toast.implicitWidth + Style.space(24)
    implicitHeight: toast.implicitHeight + Style.space(28)
    color: "transparent"
    WlrLayershell.namespace: "now-pulse-toast"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Under the bar, without pushing windows away.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    mask: Region { item: toast }

    PulseToast {
      id: toast
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: svc.barPosition === "bottom" ? undefined : parent.top
      anchors.bottom: svc.barPosition === "bottom" ? parent.bottom : undefined
      anchors.topMargin: Style.space(4)
      anchors.bottomMargin: Style.space(4)
      title: svc.toastData.title || ""
      artist: svc.toastData.artist || ""
      source: svc.toastData.source || ""
      glyph: svc.toastData.glyph || ""
      art: svc.toastData.art || ""
      hasArt: svc.toastData.hasArt === true
      canNext: svc.toastData.canNext === true
      fromBottom: svc.barPosition === "bottom"
      accent: svc.accent
      accent2: svc.accent2
      fg: Commons.Color.foreground
      bg: Commons.Color.background
      fontFamily: svc.fontFamily
      seconds: svc.toastSeconds
      Component.onCompleted: svc.toastItem = toast
      onActivated: svc.cardRequested()
      onNextRequested: { svc.next(); hide() }
      onDismissed: svc.toastUp = false
    }
  }
  // A card opening takes over from the pop-up.
  onOpenCardsChanged: if (openCards > 0) hideToast()

  onArtUrlChanged: fetchArt()
  onCoverColorsChanged: fetchArt()
  onDarkThemeChanged: sampleColors()
  Component.onCompleted: fetchArt()
}
