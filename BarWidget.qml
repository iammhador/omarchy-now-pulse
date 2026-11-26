// Now Pulse: now playing from every audio source, in the Omarchy bar.
//
// Bar:  the cover (album art or the video's thumbnail) with progress drawn
//       around it, the app's icon on its corner, and "Title — Artist" in a
//       ping-pong marquee. A small count shows when more than one source is
//       open. Left click opens the card, middle click plays/pauses, right
//       click skips, scroll changes volume, track or source.
// Card: a chip per source across the top (click to switch, middle click to
//       play/pause that one), the cover glowing in its own two colors over a
//       blurred copy of itself, seek, shuffle / previous / play / next /
//       repeat, volume, and a button to bring the app forward. For browsers
//       and video players, Video swaps the cover for a live view of the
//       window: scroll to zoom in on the video, drag to frame it.
//
// Works with anything that speaks MPRIS: Brave, Zen, Firefox, Chrome,
// Spotify, mpv, VLC, YouTube Music, ... No accounts, no network.
//
// Shared state and every side effect live in Service.qml, created once by the
// shell. This file is the per-monitor UI on top of it.

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Hyprland
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.iammhador.now-pulse"

  // ---------------------------------------------------------------- service

  property var svc: null
  property int resolveTries: 0

  function resolveService() {
    if (svc) return
    if (bar && bar.shell && typeof bar.shell.serviceFor === "function")
      svc = bar.shell.serviceFor(moduleName) || null
  }

  // The service can finish loading after the widget; look again until it's up.
  Timer {
    interval: 250
    repeat: true
    running: root.svc === null && !localService.active
    onTriggered: {
      root.resolveService()
      // Still nothing after 5 s: the shell couldn't start it, so host one here
      // (per monitor, but better than an empty bar).
      if (!root.svc && ++root.resolveTries >= 20) localService.active = true
    }
  }
  Loader {
    id: localService
    active: false
    source: "Service.qml"
    onLoaded: if (!root.svc) root.svc = item
  }

  onBarChanged: resolveService()
  onSvcChanged: pushConfig()
  Component.onCompleted: resolveService()
  Component.onDestruction: if (svc) {
    if (viewing) svc.cardOpened(false)
    if (popupOpen) svc.freeze(false)
  }

  // ---------------------------------------------------------------- player

  readonly property var player: svc ? svc.player : null
  readonly property var players: svc ? svc.players : []
  readonly property int count: players.length
  readonly property bool running: svc ? svc.running : false
  readonly property bool playing: svc ? svc.playing : false
  readonly property string title: svc ? svc.title : ""
  readonly property string artist: svc ? svc.artist : ""
  readonly property string album: svc ? svc.album : ""
  readonly property string artUrl: svc ? svc.artUrl : ""
  readonly property string trackKey: svc ? svc.trackKey : ""
  readonly property real duration: svc ? svc.duration : 0
  readonly property real position: svc ? svc.position : 0
  readonly property real progress: svc ? svc.progress : 0
  readonly property real volume: svc ? svc.volume : 0
  readonly property bool volumeSupported: svc ? svc.volumeSupported : false
  readonly property string appName: svc ? svc.appName : ""
  readonly property string appGlyph: svc ? svc.appGlyph : "󰝚"
  readonly property string appIcon: svc ? svc.appIcon : ""
  readonly property string sourceLabel: svc ? svc.sourceLabel : ""
  readonly property string site: svc ? svc.site : ""
  readonly property string siteGlyph: svc ? svc.siteGlyph : ""
  readonly property string displayTitle: svc ? svc.displayTitle : ""
  readonly property bool live: svc ? svc.live : false
  readonly property bool timeless: svc ? svc.timeless : false
  readonly property bool hasArt: svc ? svc.hasArt : false
  readonly property bool artLogo: svc ? svc.artLogo : false
  // What the player is called in messages: "YouTube", else the app.
  readonly property string sourceName: site || appName

  // ---------------------------------------------------------------- settings

  // `omarchy bar set` stores plain strings, so accept "false" / "0" too.
  function flag(name, fallback) {
    var v = setting(name, fallback)
    if (typeof v === "string") return !/^(false|0|no|off)$/i.test(v.trim())
    return !!v
  }
  function choice(name, fallback, options) {
    var v = String(setting(name, fallback)).trim().toLowerCase()
    return options.indexOf(v) !== -1 ? v : fallback
  }

  readonly property int maxWidth: Model.clamp(Number(setting("maxWidth", 240)) || 240, 80, 800)
  readonly property bool showArtist: flag("showArtist", true)
  readonly property bool marquee: flag("marquee", true)
  readonly property bool showWhenIdle: flag("showWhenIdle", false)
  readonly property bool showAppIcon: flag("showAppIcon", true)
  readonly property bool pillProgress: flag("pillProgress", true)
  readonly property bool coverColors: flag("coverColors", true)
  readonly property bool blurBackdrop: flag("blurBackdrop", true)
  readonly property bool skipSpotify: flag("skipSpotify", false)
  readonly property bool pauseOthers: flag("pauseOthers", false)
  readonly property string scrollAction: choice("scrollAction", "volume", ["volume", "track", "source", "none"])
  readonly property bool trackToast: flag("trackToast", true)
  readonly property int toastSeconds: Model.clamp(Number(setting("toastSeconds", 4)) || 4, 2, 15)

  readonly property var serviceConfig: ({
    skipSpotify: skipSpotify, pauseOthers: pauseOthers,
    coverColors: coverColors, pillProgress: pillProgress,
    trackToast: trackToast, toastSeconds: toastSeconds,
    barPosition: bar && bar.position ? String(bar.position) : "top",
    fontFamily: fontFamily
  })
  onServiceConfigChanged: pushConfig()
  function pushConfig() { if (svc) svc.configure(serviceConfig) }

  // ---------------------------------------------------------------- look

  readonly property color barFg: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color panelFg: bar ? bar.foreground : Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool darkTheme: Commons.Color.background.hslLightness < 0.5
  readonly property bool motion: !Style.reduceMotion

  // Two cover colors, crossfading between tracks.
  property color animatedAccent: svc ? svc.accent : Commons.Color.accent
  property color animatedAccent2: svc ? svc.accent2 : Commons.Color.accent
  Behavior on animatedAccent { ColorAnimation { duration: Style.duration(600); easing.type: Easing.OutCubic } }
  Behavior on animatedAccent2 { ColorAnimation { duration: Style.duration(600); easing.type: Easing.OutCubic } }

  // ---------------------------------------------------------------- actions

  property bool popupOpen: false
  readonly property bool opened: popupOpen
  // The bar underlines a widget while its panel is open. The cover and card
  // already show that, so ask for a zero-length mark (the bar rounds it).
  readonly property real openPanelIndicatorWidth: 0.01
  readonly property real openPanelIndicatorHeight: 0.01
  property real volumeFlash: 0

  function open() { if (running) popupOpen = true }
  function close() { popupOpen = false }
  function toggle() { if (running) popupOpen = !popupOpen }
  onRunningChanged: if (!running) close()

  // The pop-up was clicked: open the card on the monitor that has focus.
  readonly property string monitorName: {
    var w = root.QsWindow.window
    return w && w.screen ? String(w.screen.name) : ""
  }
  Connections {
    target: root.svc
    function onCardRequested() {
      var focused = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
      if (root.monitorName === "") { root.open(); return }
      if (focused !== "") {
        if (root.monitorName === focused) root.open()
        return
      }
      if (Quickshell.screens.length === 0 || root.monitorName === Quickshell.screens[0].name) root.open()
    }
  }

  function playPause() { if (svc) svc.playPause() }
  function next() {
    if (!running) return
    if (!player.canGoNext) { notice("Can't skip on " + sourceName); return }
    svc.next()
  }
  function previous() { if (svc) svc.previous() }
  function seekTo(seconds) {
    if (!running) return
    if (live) { notice("Live · no timeline to seek"); return }
    if (timeless) { notice(sourceName + " doesn't share a timeline"); return }
    if (!player.canSeek) { notice("Can't seek on " + sourceName); return }
    svc.seekTo(seconds)
  }
  function setVolume(v) {
    if (!running) return
    if (!volumeSupported) { notice(sourceName + " doesn't share its volume"); return }
    svc.setVolume(v)
    volumeFlash = 1
    volumeFlashTimer.restart()
  }
  function nudgeVolume(delta) { if (running) setVolume(volume + delta) }
  function toggleShuffle() { if (svc) svc.toggleShuffle() }
  function cycleRepeat() { if (svc) svc.cycleRepeat() }
  function cycleSource(dir) { if (svc) svc.cycleSource(dir) }
  function raiseApp() { if (svc) svc.raise() }

  // A short message where the user is looking: over the card when it's
  // open, else as the bar tooltip.
  function notice(text) {
    if (popupOpen) { toast(text); return }
    if (!bar) return
    bar.showTooltip(root, text)
    noticeTimer.restart()
  }
  Timer {
    id: noticeTimer
    interval: 1600
    onTriggered: if (root.bar) root.bar.hideTooltip(root)
  }
  property string toastText: ""
  function toast(text) {
    toastText = text
    toastAnim.restart()
  }

  // Video mode: the card shows a live view of the player's window. Offered
  // only when that window is known for sure. With no cover art it opens in
  // Video by itself; your own choice holds until the source changes.
  readonly property bool hasVideo: svc ? svc.hasVideo : false
  readonly property bool videoPossible: svc ? svc.videoPossible : false
  readonly property bool videoTabHidden: svc ? svc.videoTabHidden : false
  property string viewChoice: ""          // "", "cover" or "video"
  readonly property bool showVideo: hasVideo && (viewChoice === "video" || (viewChoice === "" && !hasArt && !videoTabHidden))
  readonly property string sourceKey: svc ? svc.playerKey : ""
  onSourceKeyChanged: viewChoice = ""
  function setVideo(on) {
    if (on && !hasVideo) { toast("Can't tell which window is playing this"); return }
    viewChoice = on ? "video" : "cover"
  }
  function toggleVideo() { setVideo(!showVideo) }

  // Shortcuts sheet over the card.
  property bool helpOpen: false

  Timer {
    id: volumeFlashTimer
    interval: 1100
    onTriggered: root.volumeFlash = 0
  }

  onPopupOpenChanged: {
    if (popupOpen) hoverOpen = false
    else helpOpen = false
    // The card never switches source under the pointer.
    if (svc) svc.freeze(popupOpen)
  }

  // Hover preview: a small card with the cover, title and time, after a
  // short hover over the pill.
  property bool hoverOpen: false
  // Someone can see a moving playhead: the service updates it quickly.
  readonly property bool viewing: popupOpen || hoverOpen
  onViewingChanged: if (svc) svc.cardOpened(viewing)

  Timer {
    id: hoverTimer
    interval: 450
    onTriggered: {
      // Not over another open panel: opening would close it.
      if (mouse.containsMouse && root.running && !root.popupOpen
          && root.bar && !root.bar.activePopout) root.hoverOpen = true
    }
  }
  QtObject {
    id: hoverOwner
    function close() { root.hoverOpen = false }
  }

  // Players blank their metadata for a moment between tracks. Ride that out
  // instead of hiding the pill (and losing its text) for a frame.
  property bool bridging: false
  readonly property bool hasTitle: title !== ""
  onHasTitleChanged: {
    bridging = !hasTitle && running
    if (bridging) bridgeTimer.restart()
  }
  Timer {
    id: bridgeTimer
    interval: 1500
    onTriggered: root.bridging = false
  }

  // ---------------------------------------------------------------- ipc

  IpcHandler {
    target: "now-pulse"
    function toggle(): void { root.toggle() }
    function close(): void { root.close() }
    function playPause(): void { root.playPause() }
    function next(): void { root.next() }
    function previous(): void { root.previous() }
    function shuffle(): void { root.toggleShuffle() }
    function repeat(): void { root.cycleRepeat() }
    function volume(percent: int): void { root.setVolume(percent / 100) }
    // Switch the bar to the next open source.
    function cycleSource(): void { root.cycleSource(1) }
    // Bring the current source's app forward.
    function raise(): void { root.raiseApp() }
    // Swap the card's cover for a live view of the video window.
    function video(): void { root.toggleVideo() }
    // Show the track-change pop-up for what's playing now.
    function toast(): void { if (root.svc) root.svc.showToast() }
    // Screenshot mode: show only players named *.demo (tools/fake-player.py).
    function demo(on: bool): void { if (root.svc) root.svc.demoOnly = on }
    function status(): string {
      var s = root.svc
      var list = []
      for (var i = 0; i < root.players.length; i++) {
        var p = root.players[i]
        list.push({ app: Model.appName(p), key: Model.key(p), playing: p.isPlaying, title: String(p.trackTitle || "") })
      }
      return JSON.stringify({
        running: root.running, playing: root.playing, popupOpen: root.popupOpen,
        app: root.appName, source: root.sourceLabel, pinned: s ? s.pinned : "", hold: s ? s.holdKey : "", holding: s ? s.holding : false, toast: s ? s.toastReason : "",
        title: root.title, artist: root.artist, album: root.album,
        position: Math.round(root.position * 10) / 10, duration: root.duration,
        volume: root.volumeSupported ? root.volume : null,
        accent: s ? String(s.accent) : "", accent2: s ? String(s.accent2) : "",
        video: root.showVideo, hasVideo: root.hasVideo,
        videoWindow: s && s.videoWindow ? String(s.videoWindow.title) : "",
        players: list
      })
    }
  }

  // ================================================================ BAR PILL

  readonly property bool shown: svc !== null && (running ? (displayTitle !== "" || bridging) : showWhenIdle)
  visible: shown && !vertical
  implicitWidth: shown && !vertical ? pill.width : 0
  implicitHeight: barSize

  // "Title — Artist", or "Title · YouTube" when there's no artist.
  readonly property string trackText: displayTitle
    + (showArtist && artist ? "  —  " + artist
       : (site !== "" && site !== displayTitle ? "  ·  " + site : ""))
  readonly property string pillText: running ? trackText : "Nothing playing"
  onPillTextChanged: pill.swapTrack()

  Rectangle {
    id: pill
    anchors.verticalCenter: parent.verticalCenter
    height: Math.round(root.barSize * (root.running ? 0.86 : 0.72))
    width: pillRow.width + Style.space(18)
    radius: height / 2
    // No hover or open highlight: the cover and text carry the widget.
    color: "transparent"
    opacity: root.running ? 1 : 0.55
    Behavior on width { NumberAnimation { duration: Style.duration(260); easing.type: Easing.OutCubic } }

    // Shown text lags `pillText` so the swap can animate out and back in.
    property string displayText: root.pillText

    function swapTrack() {
      if (displayText === root.pillText) return
      if (root.running && root.displayTitle === "") return   // between tracks: keep the old text
      if (!root.visible || !root.motion) { displayText = root.pillText; return }
      swapAnim.restart()
    }

    Row {
      id: pillRow
      anchors.centerIn: parent
      spacing: Style.space(8)

      // The cover with progress around its four sides, and the app's badge.
      Item {
        id: coverBox
        visible: root.running
        width: pill.height - Style.space(2)
        height: width
        anchors.verticalCenter: parent.verticalCenter

        PulseBarCover {
          anchors.fill: parent
          source: root.visible ? root.artUrl : ""
          track: root.trackKey
          playing: root.playing
          live: root.visible
          showOutline: root.pillProgress && root.duration > 0 || volumeMode
          volumeMode: root.volumeFlash > 0
          fraction: volumeMode ? root.volume : root.progress
          levels: []
          fg: root.barFg
          accent: root.animatedAccent
        }

        // App badge on the corner: where the sound comes from.
        Rectangle {
          id: badge
          // A logo standing in for art already says which app; don't say it twice.
          visible: root.showAppIcon && !root.artLogo
          readonly property real size: Math.max(Style.space(11), Math.round(coverBox.width * 0.40))
          width: size
          height: size
          radius: size / 2
          x: coverBox.width - size * 0.66
          y: coverBox.height - size * 0.66
          color: Commons.Color.background
          border.width: Math.max(1, Style.space(1))
          border.color: Util.alpha(root.barFg, 0.18)

          Image {
            id: badgeImg
            anchors.centerIn: parent
            width: parent.width - Style.space(3)
            height: width
            source: root.appIcon
            sourceSize: Qt.size(32, 32)
            asynchronous: true
            smooth: true
            visible: status === Image.Ready
          }
          Text {
            anchors.centerIn: parent
            visible: !badgeImg.visible
            text: root.appGlyph
            color: root.animatedAccent
            font.family: root.fontFamily
            font.pixelSize: Math.round(badge.size * 0.66)
          }
          // Pop when the source changes.
          property string forKey: root.svc ? root.svc.playerKey : ""
          onForKeyChanged: if (root.motion && visible) badgePop.restart()
          SequentialAnimation {
            id: badgePop
            NumberAnimation { target: badge; property: "scale"; from: 0.4; to: 1.2; duration: 160; easing.type: Easing.OutQuad }
            NumberAnimation { target: badge; property: "scale"; to: 1; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2 }
          }
        }
      }

      // Idle: a soft note in place of the cover.
      Text {
        visible: !root.running
        anchors.verticalCenter: parent.verticalCenter
        text: "󰝚"
        color: root.barFg
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      PulseMarquee {
        id: barLabel
        width: Math.min(implicitWidth, root.maxWidth)
        anchors.verticalCenter: parent.verticalCenter
        text: pill.displayText
        color: root.barFg
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        active: root.marquee && root.playing && !root.popupOpen
      }

      // More than one source open: how many.
      Rectangle {
        id: countDot
        visible: root.count > 1
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(height, countText.implicitWidth + Style.space(8))
        height: Math.round(pill.height * 0.5)
        radius: height / 2
        // Neutral: a count, not a notification.
        color: Util.alpha(root.barFg, 0.12)
        border.width: 1
        border.color: Util.alpha(root.barFg, 0.18)
        Text {
          id: countText
          anchors.centerIn: parent
          text: root.count
          color: Util.alpha(root.barFg, 0.75)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.features: { "tnum": 1 }
        }
      }
    }

    SequentialAnimation {
      id: swapAnim
      readonly property Item label: barLabel.content
      ParallelAnimation {
        NumberAnimation { target: swapAnim.label; property: "y"; to: -swapAnim.label.height * 0.8; duration: 150; easing.type: Easing.InCubic }
        NumberAnimation { target: swapAnim.label; property: "opacity"; to: 0; duration: 150 }
      }
      ScriptAction { script: { pill.displayText = root.pillText; swapAnim.label.y = swapAnim.label.height * 0.8 } }
      ParallelAnimation {
        NumberAnimation { target: swapAnim.label; property: "y"; to: 0; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
        NumberAnimation { target: swapAnim.label; property: "opacity"; to: 1; duration: 220 }
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: root.running ? Qt.PointingHandCursor : Qt.ArrowCursor
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
      onClicked: function(m) {
        if (m.button === Qt.MiddleButton) root.playPause()
        else if (m.button === Qt.RightButton) root.next()
        else root.toggle()
      }
      onWheel: function(w) {
        if (!root.running) return
        var up = w.angleDelta.y > 0
        if (root.scrollAction === "volume") root.nudgeVolume(up ? 0.05 : -0.05)
        else if (root.scrollAction === "track") { if (up) root.previous(); else root.next() }
        else if (root.scrollAction === "source") root.cycleSource(up ? -1 : 1)
      }
      onEntered: {
        if (root.running) hoverTimer.restart()
        else if (root.bar) root.bar.showTooltip(root, "Nothing playing")
      }
      onExited: {
        hoverTimer.stop()
        root.hoverOpen = false
        if (root.bar) root.bar.hideTooltip(root)
      }
      onPressed: {
        hoverTimer.stop()
        root.hoverOpen = false
        if (root.bar) root.bar.hideTooltip(root)
      }
    }
  }

  // ================================================================ CARD
  //
  // Sources across the top, then the cover as the hero, glowing in its own
  // colors over a blurred copy of itself that fills the card.

  KeyboardPanel {
    id: card
    anchorItem: pill
    owner: root
    bar: root.bar
    open: root.popupOpen
    focusTarget: keys
    contentWidth: card.fittedContentWidth(Style.space(root.showVideo ? 560 : 340))
    contentHeight: card.fittedContentHeight(content.implicitHeight)

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: function(e) { if (root.helpOpen) root.helpOpen = false; else root.close(); e.accepted = true }
      Keys.onSpacePressed: function(e) { root.playPause(); e.accepted = true }
      Keys.onLeftPressed: function(e) { root.seekTo(root.position - 5); e.accepted = true }
      Keys.onRightPressed: function(e) { root.seekTo(root.position + 5); e.accepted = true }
      Keys.onUpPressed: function(e) { root.nudgeVolume(0.05); e.accepted = true }
      Keys.onDownPressed: function(e) { root.nudgeVolume(-0.05); e.accepted = true }
      Keys.onTabPressed: function(e) { root.cycleSource(1); e.accepted = true }
      Keys.onBacktabPressed: function(e) { root.cycleSource(-1); e.accepted = true }
      Keys.onPressed: function(e) {
        if (e.key >= Qt.Key_0 && e.key <= Qt.Key_9) root.seekTo(root.duration * (e.key - Qt.Key_0) / 10)
        else if (e.key === Qt.Key_N) root.next()
        else if (e.key === Qt.Key_P) root.previous()
        else if (e.key === Qt.Key_S) root.toggleShuffle()
        else if (e.key === Qt.Key_R) root.cycleRepeat()
        else if (e.key === Qt.Key_O) { root.raiseApp(); root.close() }
        else if (e.key === Qt.Key_V) root.toggleVideo()
        else if (e.key === Qt.Key_Question || e.key === Qt.Key_Slash) root.helpOpen = !root.helpOpen
        else return
        e.accepted = true
      }
    }

    // ---- Backdrop: the blurred cover tints the whole card ---------------
    Item {
      id: backdrop
      anchors.fill: parent
      anchors.margins: -card.padding
      visible: root.blurBackdrop && backdropSrc.status === Image.Ready
      // The popup doesn't clip, and the blur reaches well past its source.
      clip: true
      layer.enabled: Style.cornerRadius > 0
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: backdropMask
      }

      Image {
        id: backdropSrc
        anchors.fill: parent
        source: root.popupOpen && root.blurBackdrop ? root.artUrl : ""
        sourceSize: Qt.size(64, 64)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
      }
      MultiEffect {
        anchors.fill: parent
        anchors.margins: -Style.space(40)
        source: backdropSrc
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        saturation: 0.25
        opacity: 0.9
      }
      // Scrim so text stays readable on any cover.
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0.0; color: Util.alpha(Commons.Color.background, root.darkTheme ? 0.45 : 0.35) }
          GradientStop { position: 0.55; color: Util.alpha(Commons.Color.background, root.darkTheme ? 0.72 : 0.6) }
          GradientStop { position: 1.0; color: Util.alpha(Commons.Color.background, root.darkTheme ? 0.88 : 0.8) }
        }
      }
    }
    Item {
      id: backdropMask
      anchors.fill: backdrop
      layer.enabled: true
      visible: false
      Rectangle { anchors.fill: parent; radius: Style.cornerRadius }
    }

    Column {
      id: content
      width: parent.width
      spacing: Style.space(14)

      // ---- Sources: one chip per open player, and Cover / Video ----------
      Item {
        width: parent.width
        height: Math.max(sources.height, viewToggle.height)

      Flickable {
        id: sources
        width: parent.width - (viewToggle.visible ? viewToggle.width + Style.space(8) : 0)
        anchors.verticalCenter: parent.verticalCenter
        height: sourceRow.height
        contentWidth: sourceRow.width
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width
        clip: true

        Row {
          id: sourceRow
          spacing: Style.space(6)

          Repeater {
            // The one shown first (never scrolled out of sight), then the
            // playing ones, then the most recently played.
            model: {
              var s = root.svc
              var list = root.players.slice()
              if (!s) return list
              list.sort(function(a, b) {
                var ca = Model.key(a) === s.playerKey, cb = Model.key(b) === s.playerKey
                if (ca !== cb) return ca ? -1 : 1
                if (a.isPlaying !== b.isPlaying) return a.isPlaying ? -1 : 1
                return (s.lastPlayed[Model.key(b)] || 0) - (s.lastPlayed[Model.key(a)] || 0)
              })
              return list
            }

            Rectangle {
              id: chip
              required property var modelData
              readonly property string k: Model.key(modelData)
              readonly property bool current: root.svc !== null && k === root.svc.playerKey
              readonly property bool on: !!modelData && modelData.isPlaying
              readonly property string icon: root.svc ? root.svc.iconFor(modelData) : ""

              // Paused for over half an hour: still there, but quiet.
              opacity: on || current || !root.svc || root.svc.pausedFor(modelData) < 1800000 ? 1 : 0.5
              implicitWidth: chipRow.implicitWidth + Style.space(20)
              implicitHeight: Math.max(Style.space(28), chipRow.implicitHeight + Style.space(12))
              width: implicitWidth
              height: implicitHeight
              radius: height / 2
              color: current ? Util.alpha(root.animatedAccent, 0.22) : Util.alpha(root.panelFg, chipArea.containsMouse ? 0.12 : 0.06)
              border.width: 1
              border.color: current ? Util.alpha(root.animatedAccent, 0.55) : Util.alpha(root.panelFg, 0.10)
              scale: chipArea.pressed ? 0.94 : 1
              Behavior on color { ColorAnimation { duration: Style.duration(200) } }
              Behavior on border.color { ColorAnimation { duration: Style.duration(200) } }
              Behavior on scale { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutBack; easing.overshoot: 3 } }

              Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: Style.space(6)

                Item {
                  width: Style.font.body + Style.space(2)
                  height: width
                  anchors.verticalCenter: parent.verticalCenter
                  Image {
                    id: chipImg
                    anchors.fill: parent
                    source: chip.icon
                    sourceSize: Qt.size(32, 32)
                    asynchronous: true
                    visible: status === Image.Ready
                  }
                  Text {
                    anchors.centerIn: parent
                    visible: !chipImg.visible
                    text: Model.appGlyph(chip.modelData)
                    color: chip.current ? root.animatedAccent : root.panelFg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  // The site ("YouTube"), with the app as the icon.
                  text: {
                    var l = root.svc ? root.svc.labelFor(chip.modelData) : Model.appName(chip.modelData)
                    return l.length > 14 ? l.slice(0, 13) + "…" : l
                  }
                  textFormat: Text.PlainText
                  color: chip.current ? root.animatedAccent : Util.alpha(root.panelFg, 0.85)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: chip.current
                }
                // Playing: three tiny bars that bounce.
                Item {
                  visible: chip.on
                  width: Style.space(10)
                  height: Style.space(9)
                  anchors.verticalCenter: parent.verticalCenter
                  Repeater {
                    model: 3
                    Rectangle {
                      required property int index
                      width: Math.max(2, Style.space(2))
                      radius: width / 2
                      x: index * (width + Style.space(1.5))
                      anchors.bottom: parent.bottom
                      color: chip.current ? root.animatedAccent : Util.alpha(root.panelFg, 0.7)
                      height: chip.on ? parent.height * (0.35 + 0.65 * level) : width
                      property real level: 0.5
                      SequentialAnimation on level {
                        running: chip.on && root.popupOpen && root.motion
                        loops: Animation.Infinite
                        NumberAnimation { to: 1; duration: 260 + index * 90; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0.15; duration: 300 + index * 70; easing.type: Easing.InOutSine }
                      }
                    }
                  }
                }
              }

              MouseArea {
                id: chipArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                onClicked: function(m) {
                  if (!root.svc) return
                  if (m.button === Qt.MiddleButton) root.svc.playPauseKey(chip.k)
                  else root.svc.pin(chip.k)
                }
              }
            }
          }
        }
      }

        // Cover / Video: a two-way switch, shown when there's a window to mirror.
        Rectangle {
          id: viewToggle
          visible: root.videoPossible
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: toggleRow.implicitWidth + Style.space(6)
          height: toggleRow.implicitHeight + Style.space(6)
          radius: height / 2
          color: Util.alpha(root.panelFg, 0.06)
          border.width: 1
          border.color: Util.alpha(root.panelFg, 0.10)

          // Sliding highlight under the active half.
          Rectangle {
            readonly property var target: root.showVideo ? videoHalf : coverHalf
            x: toggleRow.x + target.x
            y: toggleRow.y
            width: target.width
            height: target.height
            radius: height / 2
            color: Util.alpha(root.animatedAccent, 0.25)
            border.width: 1
            border.color: Util.alpha(root.animatedAccent, 0.55)
            Behavior on x { NumberAnimation { duration: Style.duration(260); easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: Style.duration(260); easing.type: Easing.OutCubic } }
          }
          Row {
            id: toggleRow
            anchors.centerIn: parent
            Repeater {
              model: [{ video: false, icon: "󰋩", label: "Cover" }, { video: true, icon: "󰕧", label: "Video" }]
              Item {
                id: half
                required property var modelData
                readonly property bool on: root.showVideo === modelData.video
                opacity: modelData.video && !root.hasVideo ? 0.45 : 1
                Component.onCompleted: if (modelData.video) videoHalf.target = half; else coverHalf.target = half
                implicitWidth: halfRow.implicitWidth + Style.space(16)
                implicitHeight: halfRow.implicitHeight + Style.space(8)
                width: implicitWidth
                height: implicitHeight
                Row {
                  id: halfRow
                  anchors.centerIn: parent
                  spacing: Style.space(5)
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: half.modelData.icon
                    color: half.on ? root.animatedAccent : Util.alpha(root.panelFg, 0.7)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: half.modelData.label
                    color: half.on ? root.animatedAccent : Util.alpha(root.panelFg, 0.7)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: half.on
                  }
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setVideo(half.modelData.video)
                }
              }
            }
          }
          // Stand-ins the highlight follows (set once the halves exist).
          QtObject { id: coverHalf; property Item target: null; readonly property real x: target ? target.x : 0; readonly property real width: target ? target.width : 0; readonly property real height: target ? target.height : 0 }
          QtObject { id: videoHalf; property Item target: null; readonly property real x: target ? target.x : 0; readonly property real width: target ? target.width : 0; readonly property real height: target ? target.height : 0 }
        }
      }

      // ---- Cover or video -------------------------------------------------
      Item {
        id: stage
        width: parent.width
        // Video: 16:9. Square art gets a square-ish stage; thumbnails a wide one.
        height: Math.round(root.showVideo ? width * 9 / 16
          : !root.hasArt ? width / 2
          : hero.aspect > 1.01 ? (width - Style.space(16)) / hero.aspect + Style.space(16)
          : width * 0.9)
        Behavior on height { NumberAnimation { duration: Style.duration(380); easing.type: Easing.OutCubic } }

        Loader {
          anchors.fill: parent
          active: root.showVideo && root.popupOpen
          sourceComponent: PulseVideo {
            source: root.svc ? root.svc.videoWindow : null
            live: root.popupOpen
            view: root.svc ? root.svc.videoView : ({})
            fg: root.panelFg
            accent: root.animatedAccent
            playing: root.playing
            fontFamily: root.fontFamily
            onClicked: root.playPause()
            onDoubleClicked: { root.raiseApp(); root.close() }
            onViewEdited: function(view) { if (root.svc) root.svc.saveVideoView(view) }
            tabHidden: root.svc ? root.svc.videoTabHidden : false
            canShowTab: root.svc ? root.svc.canShowTab : false
            appName: root.appName
            onShowTab: if (root.svc) root.svc.showVideoTab()
          }
        }

        // No art, or only a logo: a title card in the theme's colors.
        Rectangle {
          id: titleCard
          visible: !root.showVideo && !root.hasArt
          anchors.fill: parent
          radius: Math.max(Style.cornerRadius, Style.space(14))
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Util.alpha(Commons.Color.accent, 0.30) }
            GradientStop { position: 1.0; color: Util.alpha(Commons.Color.accent, 0.08) }
          }
          border.width: 1
          border.color: Util.alpha(Commons.Color.accent, 0.25)

          // Just the source: the title sits right below the stage.
          Column {
            anchors.centerIn: parent
            spacing: Style.space(10)

            Rectangle {
              id: glyphTile
              anchors.horizontalCenter: parent.horizontalCenter
              width: Style.space(64)
              height: width
              radius: Style.space(16)
              color: Util.alpha(Commons.Color.background, 0.55)
              border.width: 1
              border.color: Util.alpha(Commons.Color.accent, 0.35)
              // The platform's glyph; an unknown site shows its initial.
              Text {
                anchors.centerIn: parent
                readonly property bool initial: root.siteGlyph === "" && root.site !== ""
                text: initial ? root.site.charAt(0).toUpperCase() : (root.siteGlyph || root.appGlyph)
                color: Commons.Color.accent
                font.family: root.fontFamily
                font.bold: initial
                font.pixelSize: initial ? Style.font.title + Style.space(12) : Style.font.iconLarge + Style.space(12)
              }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.sourceLabel
              color: Util.alpha(root.panelFg, 0.75)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1
              font.capitalization: Font.AllUppercase
            }
          }
        }

        PulseCover {
          id: hero
          visible: !root.showVideo && root.hasArt
          anchors.fill: parent
          source: root.popupOpen ? root.artUrl : ""
          playing: root.playing
          live: root.popupOpen
          vinyl: false
          accent: root.animatedAccent
          accent2: root.animatedAccent2
          fg: root.panelFg
          hole: Commons.Color.background
          fontFamily: root.fontFamily
          energy: 0
          onDoubleClicked: { root.raiseApp(); root.close() }
          onSkip: function(dir) { if (dir > 0) root.next(); else root.previous() }
        }
      }

      // ---- Title / artist / source --------------------------------------
      Item {
        id: info
        width: parent.width
        height: infoCol.implicitHeight

        Column {
          id: infoCol
          width: parent.width
          spacing: Style.space(3)

          // Two lines, then an ellipsis: long titles read at a glance.
          Text {
            width: parent.width
            text: root.displayTitle || "Nothing playing"
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            color: root.panelFg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title + Style.space(4)
            font.bold: true
          }
          Text {
            width: parent.width
            visible: text !== ""
            text: root.artist + (root.album && root.album !== root.title ? "  ·  " + root.album : "")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Util.alpha(root.panelFg, 0.62)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          // Source: the glyph carries the color; the words stay readable.
          Row {
            width: parent.width
            spacing: Style.space(6)
            Text {
              id: srcGlyph
              anchors.verticalCenter: parent.verticalCenter
              text: root.siteGlyph || root.appGlyph
              color: root.animatedAccent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - srcGlyph.width - parent.spacing
              text: root.sourceLabel
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: Util.alpha(root.panelFg, 0.62)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 0.4
            }
          }
        }
      }

      // ---- Live: no timeline, so say it --------------------------------
      Rectangle {
        visible: root.live
        width: liveRow.implicitWidth + Style.space(18)
        height: liveRow.implicitHeight + Style.space(8)
        radius: height / 2
        color: Util.alpha(root.animatedAccent, 0.16)
        border.width: 1
        border.color: Util.alpha(root.animatedAccent, 0.45)
        Row {
          id: liveRow
          anchors.centerIn: parent
          spacing: Style.space(6)
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(7)
            height: width
            radius: width / 2
            color: root.animatedAccent
            opacity: root.playing ? 1 : 0.4
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.playing ? "LIVE" : "LIVE  ·  PAUSED"
            color: root.panelFg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 0.8
          }
        }
      }

      // ---- Seek -----------------------------------------------------------
      Column {
        id: seek
        width: parent.width
        spacing: Style.space(2)
        visible: root.duration > 0

        PulseSlider {
          id: seekSlider
          width: parent.width
          value: root.position
          maximum: Math.max(1, root.duration)
          fill: root.animatedAccent
          fill2: root.animatedAccent2
          track: Util.alpha(root.panelFg, 0.15)
          enabled: root.running && !!root.player && root.player.canSeek && root.duration > 0
          onReleased: function(v) { root.seekTo(v) }

          Rectangle {
            id: seekBubble
            z: 10
            opacity: (seekSlider.hovering || seekSlider.dragging) && root.duration > 0 ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Style.duration(140) } }
            width: bubbleText.implicitWidth + Style.space(18)
            height: bubbleText.implicitHeight + Style.space(10)
            radius: Style.space(8)
            x: Model.clamp(seekSlider.previewX - width / 2, 0, seekSlider.width - width)
            y: -height - Style.space(6)
            color: Util.alpha(Commons.Color.background, 0.94)
            border.width: 1
            border.color: Util.alpha(root.animatedAccent, 0.45)
            Text {
              id: bubbleText
              anchors.centerIn: parent
              text: Model.timestamp(seekSlider.previewValue)
              color: root.animatedAccent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              font.features: { "tnum": 1 }
            }
          }
        }
        Item {
          width: parent.width
          height: elapsed.implicitHeight
          Text {
            id: elapsed
            text: Model.timestamp(root.position)
            color: Util.alpha(root.panelFg, 0.55)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.features: { "tnum": 1 }
          }
          Text {
            anchors.right: parent.right
            text: "-" + Model.timestamp(root.duration - root.position)
            color: Util.alpha(root.panelFg, 0.55)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.features: { "tnum": 1 }
          }
        }
      }

      // ---- Transport ------------------------------------------------------
      Item {
        id: transport
        width: parent.width
        // Room for the progress ring around the play button.
        height: playRing.height

        PulseIconButton {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          icon: "󰒝"
          size: Style.font.icon + Style.space(2)
          color: root.panelFg
          accent: root.animatedAccent
          fontFamily: root.fontFamily
          active: root.running && !!root.player && root.player.shuffle
          visible: root.running && !!root.player && root.player.shuffleSupported
          onClicked: root.toggleShuffle()
        }

        Row {
          anchors.centerIn: parent
          spacing: Style.space(18)

          PulseIconButton {
            anchors.verticalCenter: parent.verticalCenter
            icon: "󰒮"
            size: Style.font.iconLarge + Style.space(4)
            color: root.panelFg
            accent: root.animatedAccent
            fontFamily: root.fontFamily
            enabled: root.running && !!root.player && (root.player.canGoPrevious || root.player.canSeek)
            opacity: enabled ? 1 : 0.3
            onClicked: root.previous()
          }

          // Play: two-tone disc that squishes on press and morphs its glyph.
          Rectangle {
            id: playBtn
            width: Style.space(58)
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            gradient: Gradient {
              GradientStop { position: 0.0; color: root.animatedAccent }
              GradientStop { position: 1.0; color: root.animatedAccent2 }
            }
            scale: playMouse.pressed ? 0.86 : (playMouse.containsMouse ? 1.07 : 1)
            Behavior on scale { NumberAnimation { duration: Style.duration(240); easing.type: Easing.OutBack; easing.overshoot: 3 } }

            // Progress ring around the button, echoing the bar.
            Shape {
              id: playRing
              readonly property real stroke: Math.max(1.5, Style.space(2))
              z: -1
              anchors.centerIn: parent
              width: parent.width + Style.space(14)
              height: width
              preferredRendererType: Shape.CurveRenderer
              ShapePath {
                strokeWidth: playRing.stroke
                strokeColor: Util.alpha(root.panelFg, 0.12)
                fillColor: "transparent"
                PathAngleArc {
                  centerX: playRing.width / 2; centerY: playRing.height / 2
                  radiusX: (playRing.width - playRing.stroke) / 2; radiusY: radiusX
                  startAngle: 0; sweepAngle: 360
                }
              }
              ShapePath {
                strokeWidth: playRing.stroke
                strokeColor: root.animatedAccent
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                  centerX: playRing.width / 2; centerY: playRing.height / 2
                  radiusX: (playRing.width - playRing.stroke) / 2; radiusY: radiusX
                  startAngle: -90; sweepAngle: 360 * Model.clamp(root.progress, 0, 1)
                }
              }
            }

            Text {
              id: playGlyph
              anchors.centerIn: parent
              anchors.horizontalCenterOffset: root.playing ? 0 : Style.space(2)
              text: root.playing ? "󰏤" : "󰐊"
              color: Commons.Color.background
              font.family: root.fontFamily
              font.pixelSize: Style.font.iconLarge + Style.space(8)
              onTextChanged: if (root.motion) glyphMorph.restart()
            }
            SequentialAnimation {
              id: glyphMorph
              ParallelAnimation {
                NumberAnimation { target: playGlyph; property: "scale"; from: 0.3; to: 1.15; duration: 180; easing.type: Easing.OutQuad }
                NumberAnimation { target: playGlyph; property: "rotation"; from: -90; to: 0; duration: 260; easing.type: Easing.OutBack }
              }
              NumberAnimation { target: playGlyph; property: "scale"; to: 1; duration: 140; easing.type: Easing.OutQuad }
            }

            MouseArea {
              id: playMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.playPause()
            }
          }

          PulseIconButton {
            anchors.verticalCenter: parent.verticalCenter
            icon: "󰒭"
            size: Style.font.iconLarge + Style.space(4)
            color: root.panelFg
            accent: root.animatedAccent
            fontFamily: root.fontFamily
            enabled: root.running && !!root.player && root.player.canGoNext
            opacity: enabled ? 1 : 0.3
            onClicked: root.next()
          }
        }

        PulseIconButton {
          readonly property int loop: root.running && root.player ? root.player.loopState : MprisLoopState.None
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          icon: loop === MprisLoopState.Track ? "󰑘" : "󰑖"
          size: Style.font.icon + Style.space(2)
          color: root.panelFg
          accent: root.animatedAccent
          fontFamily: root.fontFamily
          active: loop !== MprisLoopState.None
          visible: root.running && !!root.player && root.player.loopSupported
          onClicked: root.cycleRepeat()
        }
      }

      // ---- Volume ---------------------------------------------------------
      Item {
        width: parent.width
        height: volSlider.implicitHeight
        visible: root.volumeSupported

        readonly property real v: root.volume
        property real restore: 0.5

        Text {
          id: volLow
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: parent.v <= 0.001 ? "󰝟" : "󰕿"
          color: Util.alpha(root.panelFg, 0.55)
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
          MouseArea {
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              var item = parent.parent
              if (item.v > 0.001) { item.restore = item.v; root.setVolume(0) }
              else root.setVolume(item.restore)
            }
          }
        }
        PulseSlider {
          id: volSlider
          anchors.left: volLow.right
          anchors.right: volHigh.left
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          value: parent.v
          maximum: 1
          live: true
          fill: Util.alpha(root.panelFg, 0.8)
          track: Util.alpha(root.panelFg, 0.15)
          onMoved: function(v) { root.setVolume(v) }
          onReleased: function(v) { root.setVolume(v) }
        }
        Text {
          id: volHigh
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "󰕾"
          color: Util.alpha(root.panelFg, 0.55)
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }
      }

      // ---- Footer ---------------------------------------------------------
      Item {
        width: parent.width
        height: openChip.implicitHeight

        // What's worth knowing right now, or nothing.
        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - footRight.width - Style.space(10)
          text: {
            if (!root.running || !root.popupOpen) return ""   // re-read on every open
            if (!root.playing) {
              var ms = root.svc ? root.svc.pausedFor(root.player) : 0
              return ms > 0 ? "Paused  ·  " + Model.ago(ms) : "Paused"
            }
            if (root.count > 1) return root.count + " sources open"
            return ""
          }
          elide: Text.ElideRight
          color: Util.alpha(root.panelFg, 0.62)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Row {
          id: footRight
          anchors.right: parent.right
          spacing: Style.space(8)
          PulseChip {
            icon: "?"
            label: ""
            fg: root.panelFg
            accent: root.animatedAccent
            fontFamily: root.fontFamily
            active: root.helpOpen
            onClicked: root.helpOpen = !root.helpOpen
          }
        PulseChip {
          id: openChip
          icon: "󰏌"
          // The exact tab when its window is known, else just the app.
          label: root.hasVideo && root.site !== "" ? "Open " + root.site : "Open " + root.appName
          fg: root.panelFg
          accent: root.animatedAccent
          fontFamily: root.fontFamily
          onClicked: { root.raiseApp(); root.close() }
        }
        }
      }
    }

    // Toast: a short message floating over the top of the card.
    Rectangle {
      id: cardToast
      z: 30
      anchors.horizontalCenter: parent.horizontalCenter
      y: Style.space(4)
      width: Math.min(parent.width - Style.space(16), toastLabel.implicitWidth + Style.space(24))
      height: toastLabel.implicitHeight + Style.space(12)
      radius: height / 2
      color: Util.alpha(Commons.Color.background, 0.94)
      border.width: 1
      border.color: Util.alpha(root.animatedAccent, 0.55)
      opacity: 0
      visible: opacity > 0
      Text {
        id: toastLabel
        anchors.centerIn: parent
        width: Math.min(implicitWidth, cardToast.parent.width - Style.space(40))
        text: root.toastText
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.panelFg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      SequentialAnimation {
        id: toastAnim
        NumberAnimation { target: cardToast; property: "opacity"; to: 1; duration: Style.duration(160) }
        PauseAnimation { duration: 2000 }
        NumberAnimation { target: cardToast; property: "opacity"; to: 0; duration: Style.duration(400) }
      }
    }

    // Shortcuts sheet: "?" in the footer, or the ? key.
    Rectangle {
      id: help
      z: 40
      anchors.fill: parent
      anchors.margins: -card.padding
      radius: Style.cornerRadius
      color: Util.alpha(Commons.Color.background, 0.96)
      opacity: root.helpOpen ? 1 : 0
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: Style.duration(160) } }
      MouseArea { anchors.fill: parent; onClicked: root.helpOpen = false }

      Column {
        anchors.centerIn: parent
        width: parent.width - Style.space(48)
        spacing: Style.space(8)
        Text {
          text: "Shortcuts"
          color: root.panelFg
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Repeater {
          model: [
            ["Space", "Play / pause"], ["← →", "Seek 5 s"], ["↑ ↓", "Volume"],
            ["0 – 9", "Jump to 0 – 90 %"], ["N  P", "Next / previous"],
            ["Tab", "Next source"], ["V", "Cover / video"], ["O", "Open the tab or app"],
            ["Bar: middle-click", "Play / pause"], ["Bar: right-click", "Next"],
            ["Bar: scroll", "Volume (see settings)"], ["Video: scroll / drag", "Zoom / frame"],
            ["Esc", "Close"]
          ]
          Item {
            required property var modelData
            width: parent.width
            height: keyText.implicitHeight
            Text {
              id: keyText
              text: modelData[0]
              color: root.animatedAccent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
            Text {
              anchors.right: parent.right
              text: modelData[1]
              color: Util.alpha(root.panelFg, 0.8)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }
  }

  // ================================================================ HOVER PREVIEW

  PopupCard {
    id: preview
    anchorItem: pill
    owner: hoverOwner
    bar: root.bar
    triggerMode: "hover"
    open: root.hoverOpen && root.running
    contentWidth: preview.fittedContentWidth(Style.space(300))
    contentHeight: preview.fittedContentHeight(previewRow.implicitHeight)

    Row {
      id: previewRow
      width: parent.width
      spacing: Style.space(12)

      Item {
        id: previewArt
        width: Style.space(58)
        height: width
        anchors.verticalCenter: parent.verticalCenter
        layer.enabled: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: previewMask
        }
        Rectangle { anchors.fill: parent; color: Util.alpha(root.panelFg, 0.08) }
        Text {
          anchors.centerIn: parent
          text: root.appGlyph
          color: Util.alpha(root.panelFg, 0.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.iconLarge
        }
        Image {
          anchors.fill: parent
          source: root.hoverOpen ? root.artUrl : ""
          sourceSize: Qt.size(128, 128)
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
        }
      }
      Item {
        id: previewMask
        anchors.fill: previewArt
        layer.enabled: true
        visible: false
        Rectangle { anchors.fill: parent; radius: Math.max(Style.space(8), Style.cornerRadius / 2) }
      }

      Column {
        width: parent.width - previewArt.width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)

        PulseMarquee {
          width: parent.width
          text: root.displayTitle
          color: root.panelFg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body + Style.space(1)
          font.bold: true
          active: root.hoverOpen
        }
        Text {
          width: parent.width
          text: (root.artist ? root.artist + "  ·  " : "") + root.sourceLabel
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Util.alpha(root.panelFg, 0.62)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Item { width: 1; height: Style.space(4) }
        Rectangle {
          visible: root.duration > 0
          width: parent.width
          height: Math.max(2, Style.space(3))
          radius: height / 2
          color: Util.alpha(root.panelFg, 0.15)
          Rectangle {
            height: parent.height
            radius: height / 2
            width: Math.max(height, parent.width * root.progress)
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: root.animatedAccent }
              GradientStop { position: 1.0; color: root.animatedAccent2 }
            }
          }
        }
        Item {
          width: parent.width
          height: previewElapsed.implicitHeight
          Text {
            id: previewElapsed
            text: [root.playing ? "" : "Paused", root.duration > 0 ? Model.timestamp(root.position) : (root.live ? "Live" : "")].filter(function(x) { return x !== "" }).join("  ·  ")
            color: Util.alpha(root.panelFg, 0.55)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.features: { "tnum": 1 }
          }
          Text {
            anchors.right: parent.right
            visible: root.duration > 0
            text: "-" + Model.timestamp(root.duration - root.position)
            color: Util.alpha(root.panelFg, 0.55)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.features: { "tnum": 1 }
          }
          Text {
            anchors.right: parent.right
            visible: root.count > 1 && root.duration <= 0
            text: root.count + " sources"
            color: Util.alpha(root.panelFg, 0.55)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
