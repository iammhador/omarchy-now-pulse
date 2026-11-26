// The card's video view: a live mirror of the player's window. Scroll to
// zoom in on the video, drag to move it into frame. Click plays / pauses,
// double-click opens the app. The framing is handed back through `viewEdited`
// so the service can remember it per app.
import QtQuick
import QtQuick.Effects
import Quickshell.Wayland
import qs.Commons
import "Model.js" as Model

Item {
  id: v

  property var source: null            // a Wayland Toplevel
  property bool live: false
  property var view: ({ zoom: 1, x: 0, y: 0, saved: false })
  property color fg: "white"
  property color accent: "white"
  property bool playing: false
  property string fontFamily: Style.font.family
  property bool tabHidden: false       // the video's tab isn't in front
  property bool canShowTab: false
  property string appName: ""

  signal clicked()
  signal doubleClicked()
  signal viewEdited(var view)
  signal showTab()

  readonly property bool hasContent: cap.hasContent
  readonly property real radius: Math.max(Style.cornerRadius, Style.space(14))

  // Window size from the first frame; until then assume 16:9.
  readonly property real srcW: cap.sourceSize.width > 0 ? cap.sourceSize.width : 16
  readonly property real srcH: cap.sourceSize.height > 0 ? cap.sourceSize.height : 9
  // The whole window fitted into the viewport at zoom 1.
  readonly property real fitK: Math.min(width / srcW, height / srcH)
  readonly property real baseW: srcW * fitK
  readonly property real baseH: srcH * fitK

  // Framing is stored as fractions of the content, so it survives resizes.
  property real zoom: 1
  property real fx: 0
  property real fy: 0
  readonly property var px: Model.clampView({ zoom: zoom, x: fx * baseW * zoom, y: fy * baseH * zoom }, baseW, baseH, width, height)

  onViewChanged: load()
  Component.onCompleted: load()
  function load() {
    zoom = view && view.zoom ? view.zoom : 1
    fx = view && view.fx ? view.fx : 0
    fy = view && view.fy ? view.fy : 0
  }
  function apply(p, commit) {
    zoom = p.zoom
    fx = baseW > 0 ? p.x / (baseW * p.zoom) : 0
    fy = baseH > 0 ? p.y / (baseH * p.zoom) : 0
    if (commit) v.viewEdited({ zoom: zoom, fx: fx, fy: fy })
  }
  function reset() { apply({ zoom: 1, x: 0, y: 0 }, true) }

  Rectangle {
    anchors.fill: parent
    radius: v.radius
    color: Qt.rgba(0, 0, 0, 0.85)
  }

  Item {
    id: viewport
    anchors.fill: parent
    clip: true
    layer.enabled: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: mask
    }

    ScreencopyView {
      id: cap
      x: v.px.x
      y: v.px.y
      width: v.baseW * v.px.zoom
      height: v.baseH * v.px.zoom
      captureSource: v.live ? v.source : null
      live: v.live
      paintCursor: false
    }
  }
  Item {
    id: mask
    anchors.fill: viewport
    layer.enabled: true
    visible: false
    Rectangle { anchors.fill: parent; radius: v.radius }
  }

  // Waiting for the first frame, or the window can't be captured.
  Column {
    anchors.centerIn: parent
    spacing: Style.space(6)
    visible: !cap.hasContent
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "󰕧"
      color: Util.alpha(v.fg, 0.5)
      font.family: v.fontFamily
      font.pixelSize: Style.font.displayLarge
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: v.source ? "Connecting to the window…" : "No window to show"
      color: Util.alpha(v.fg, 0.5)
      font.family: v.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // Play / pause flash in the middle, like a video player.
  Rectangle {
    id: flash
    anchors.centerIn: parent
    width: Style.space(64)
    height: width
    radius: width / 2
    color: Qt.rgba(0, 0, 0, 0.55)
    opacity: 0
    scale: 0.8
    Text {
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: v.playing ? 0 : Style.space(2)
      text: v.playing ? "󰐊" : "󰏤"
      color: "white"
      font.family: v.fontFamily
      font.pixelSize: Style.font.iconLarge + Style.space(10)
    }
    ParallelAnimation {
      id: flashAnim
      NumberAnimation { target: flash; property: "opacity"; from: 1; to: 0; duration: 650; easing.type: Easing.InQuad }
      NumberAnimation { target: flash; property: "scale"; from: 0.8; to: 1.25; duration: 650; easing.type: Easing.OutCubic }
    }
  }

  // The video plays in a background tab: say so, and offer to bring it up.
  Rectangle {
    z: 5
    visible: v.tabHidden && cap.hasContent
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(12)
    width: Math.min(parent.width - Style.space(24), tabRow.implicitWidth + Style.space(20))
    height: tabRow.implicitHeight + Style.space(12)
    radius: height / 2
    color: Qt.rgba(0, 0, 0, 0.75)
    border.width: 1
    border.color: Util.alpha(v.accent, 0.5)
    Row {
      id: tabRow
      anchors.centerIn: parent
      spacing: Style.space(8)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "The video's tab is in the background"
        color: "white"
        font.family: v.fontFamily
        font.pixelSize: Style.font.caption
      }
      Rectangle {
        visible: v.canShowTab
        anchors.verticalCenter: parent.verticalCenter
        width: showLabel.implicitWidth + Style.space(14)
        height: showLabel.implicitHeight + Style.space(6)
        radius: height / 2
        color: showArea.containsMouse ? v.accent : Util.alpha(v.accent, 0.8)
        Text {
          id: showLabel
          anchors.centerIn: parent
          text: "Show tab (switches briefly)"
          color: "black"
          font.family: v.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        MouseArea {
          id: showArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: v.showTab()
        }
      }
      Text {
        visible: !v.canShowTab
        anchors.verticalCenter: parent.verticalCenter
        text: "· switch to that tab in " + v.appName
        color: Util.alpha("white", 0.7)
        font.family: v.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // Zoom level and a hint, shown while framing and fading after.
  Rectangle {
    id: hud
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(8)
    width: hudText.implicitWidth + Style.space(16)
    height: hudText.implicitHeight + Style.space(8)
    radius: height / 2
    color: Qt.rgba(0, 0, 0, 0.6)
    opacity: 0
    visible: opacity > 0
    Text {
      id: hudText
      anchors.centerIn: parent
      text: v.px.zoom > 1.01
        ? Math.round(v.px.zoom * 100) + " %  ·  drag to move  ·  right-click to reset"
        : "Scroll to zoom in on the video"
      color: "white"
      font.family: v.fontFamily
      font.pixelSize: Style.font.caption
    }
    SequentialAnimation {
      id: hudAnim
      NumberAnimation { target: hud; property: "opacity"; to: 1; duration: 120 }
      PauseAnimation { duration: 1400 }
      NumberAnimation { target: hud; property: "opacity"; to: 0; duration: 500 }
    }
  }
  onLiveChanged: if (live && cap.hasContent) hudAnim.restart()
  Connections {
    target: cap
    function onHasContentChanged() { if (cap.hasContent && v.live) hudAnim.restart() }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: dragging ? Qt.ClosedHandCursor : (v.px.zoom > 1.01 ? Qt.OpenHandCursor : Qt.PointingHandCursor)
    preventStealing: true

    property bool dragging: false
    property real sx: 0
    property real sy: 0
    property var start: null

    onPressed: function(m) {
      sx = m.x; sy = m.y
      start = v.px
      dragging = false
    }
    onPositionChanged: function(m) {
      if (!pressed || !start || (m.buttons & Qt.LeftButton) === 0) return
      var dx = m.x - sx, dy = m.y - sy
      if (!dragging && Math.abs(dx) + Math.abs(dy) > 5) dragging = true
      if (!dragging) return
      v.apply(Model.clampView({ zoom: start.zoom, x: start.x + dx, y: start.y + dy }, v.baseW, v.baseH, v.width, v.height), false)
      hud.opacity = 1
    }
    onReleased: function(m) {
      if (dragging) { dragging = false; v.apply(v.px, true); hudAnim.restart() }
    }
    onClicked: function(m) {
      if (m.button === Qt.RightButton) { v.reset(); hudAnim.restart(); return }
      clickTimer.restart()
    }
    onDoubleClicked: function(m) {
      if (m.button !== Qt.LeftButton) return
      clickTimer.stop()
      v.doubleClicked()
    }
    onWheel: function(w) {
      var f = w.angleDelta.y > 0 ? 1.15 : 1 / 1.15
      v.apply(Model.zoomAt(v.px, f, w.x, w.y, v.baseW, v.baseH, v.width, v.height), true)
      hudAnim.restart()
    }
  }
  // Single click waits a moment so a double-click doesn't also pause.
  Timer {
    id: clickTimer
    interval: 230
    onTriggered: { v.clicked(); if (!Style.reduceMotion) flashAnim.restart() }
  }
}
