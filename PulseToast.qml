// The track-change pop-up: a small card under the bar when a new track
// starts, with the cover, title, artist and where it plays. It slides in,
// waits (longer while hovered), and slides away. Click it to open the player
// card, the skip button for the next track, right-click to dismiss.
import QtQuick
import QtQuick.Effects
import qs.Commons

Item {
  id: t

  property string title: ""
  property string artist: ""
  property string source: ""         // "YouTube · Zen"
  property string glyph: ""          // site or app glyph, for no-art covers
  property string art: ""
  property bool hasArt: false
  property bool canNext: false
  property bool fromBottom: false    // bar at the bottom: slide up
  property color accent: "white"
  property color accent2: "white"
  property color fg: "white"
  property color bg: "black"
  property string fontFamily: Style.font.family
  property int seconds: 4

  signal activated()
  signal nextRequested()
  signal dismissed()

  readonly property bool hovered: hover.hovered
  readonly property real r: Math.max(Style.space(4), Style.cornerRadius)

  implicitWidth: Style.space(360)
  implicitHeight: Style.space(72)

  // ---- life: in, wait, out -------------------------------------------------
  property bool shown: false
  property real life: 1              // 1 -> 0 while waiting; drawn as a line
  function show() {
    leave.stop()
    life = 1
    shown = true
    wait.restart()
  }
  function hide() {
    if (!shown) return
    wait.stop()
    shown = false
    leave.restart()
  }
  NumberAnimation {
    id: wait
    target: t; property: "life"; from: t.life; to: 0
    duration: Math.max(1500, t.seconds * 1000) * t.life
    paused: t.hovered
    onFinished: t.hide()
  }
  // The window stays mapped until the card has slid away.
  Timer { id: leave; interval: Style.duration(260) + 20; onTriggered: t.dismissed() }
  onHoveredChanged: if (!hovered && shown && !wait.running) wait.restart()

  // ---- card ----------------------------------------------------------------
  Item {
    id: card
    width: t.width
    height: t.height
    opacity: t.shown ? 1 : 0
    y: t.shown ? 0 : (Style.reduceMotion ? 0 : (t.fromBottom ? 1 : -1) * Style.space(14))
    scale: t.shown || Style.reduceMotion ? 1 : 0.97
    Behavior on opacity { NumberAnimation { duration: Style.duration(t.shown ? 220 : 180); easing.type: Easing.OutCubic } }
    Behavior on y { NumberAnimation { duration: Style.duration(t.shown ? 320 : 200); easing.type: t.shown ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.2 } }
    Behavior on scale { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }

    Rectangle {
      id: plate
      anchors.fill: parent
      radius: t.r
      color: t.bg
      border.width: 1
      border.color: Util.alpha(t.accent, 0.35)
      clip: true

      // A wash of the cover's colors from the left.
      Rectangle {
        anchors.fill: parent
        opacity: 0.16
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: t.accent }
          GradientStop { position: 0.55; color: Util.alpha(t.accent2, 0.4) }
          GradientStop { position: 1; color: "transparent" }
        }
      }

      // Time left before it goes, as a hairline along the bottom.
      Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        height: Math.max(1, Style.space(2))
        width: parent.width * t.life
        color: t.accent
        opacity: t.hovered ? 0.35 : 0.8
      }
    }

    // Cover
    Item {
      id: cover
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: t.height - Style.space(20)
      height: width

      Rectangle {
        anchors.fill: parent
        radius: Math.max(Style.space(3), t.r - Style.space(2))
        color: Util.alpha(t.accent, 0.18)
        visible: !img.visible
        Text {
          anchors.centerIn: parent
          text: t.glyph || "󰝚"
          textFormat: Text.PlainText
          font.family: t.fontFamily
          font.pixelSize: parent.height * 0.48
          color: t.accent
        }
      }
      Image {
        id: img
        anchors.fill: parent
        source: t.hasArt ? t.art : ""
        visible: t.hasArt && status === Image.Ready
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: width * 2
        sourceSize.height: height * 2
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: coverMask }
      }
      Rectangle {
        id: coverMask
        anchors.fill: parent
        radius: Math.max(Style.space(3), t.r - Style.space(2))
        visible: false
        layer.enabled: true
      }
    }

    // Text
    Column {
      anchors.left: cover.right
      anchors.leftMargin: Style.space(12)
      anchors.right: skip.left
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: "Now playing" + (t.source !== "" ? "  ·  " + t.source : "")
        textFormat: Text.PlainText
        elide: Text.ElideRight
        font.family: t.fontFamily
        font.pixelSize: Style.font.caption
        color: t.accent
      }
      Text {
        width: parent.width
        text: t.title
        textFormat: Text.PlainText
        elide: Text.ElideRight
        font.family: t.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        color: t.fg
      }
      Text {
        width: parent.width
        visible: t.artist !== ""
        text: t.artist
        textFormat: Text.PlainText
        elide: Text.ElideRight
        font.family: t.fontFamily
        font.pixelSize: Style.font.bodySmall
        color: Util.alpha(t.fg, 0.65)
      }
    }

    PulseIconButton {
      id: skip
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      visible: t.canNext
      width: visible ? implicitWidth : 0
      icon: "󰒭"
      color: t.fg
      accent: t.accent
      fontFamily: t.fontFamily
      z: 2
      onClicked: t.nextRequested()
    }
  }

  HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
  TapHandler {
    acceptedButtons: Qt.LeftButton
    onTapped: { t.activated(); t.hide() }
  }
  TapHandler {
    acceptedButtons: Qt.RightButton | Qt.MiddleButton
    onTapped: t.hide()
  }
}
