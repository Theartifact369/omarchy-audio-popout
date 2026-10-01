import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

// System-wide audio visualizer for the Omarchy bar.
// Spawns cava in raw mode (one space-separated line of 0..32767 per frame on
// stdout) and draws the values as animated bars in the theme foreground color.
// Click (or scroll over it) opens a popout: default-sink volume slider, mute,
// an EasyEffects launch button for EQ, and a dense EasyEffects-style spectrum
// analyzer from a second cava instance that only runs while the popout is open.
// ponytail: fixed 20 bars / live bars per Repeater index lookup — no delegate
// churn per frame; upgrade to smoother interpolation/fps only if it flickers.

Item {
  id: root

  property var bar
  property string moduleName
  property var settings

  property int barCount: 20
  property int barWidth: 3
  property int gap: 2
  readonly property real maxHeight: Math.max(4, Math.round((bar ? bar.barSize : 30) * 0.78))
  property bool gone: false

  // Popout state: default sink volume/mute, same service the audio panel uses.
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property real outputVolume: sink && sink.audio ? sink.audio.volume : 0
  readonly property bool outputMuted: sink && sink.audio ? sink.audio.muted : false
  readonly property string sinkName: sink ? String(sink.description || sink.name || "") : ""
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property bool popoutOpen: false
  property int popoutBarCount: 56
  property var popLevels: []
  // Conf paths resolve next to this file, so the module is location-independent.
  readonly property string barConfPath: decodeURIComponent(String(Qt.resolvedUrl("cava.conf")).replace(/^file:\/\//, ""))
  readonly property string popoutConfPath: decodeURIComponent(String(Qt.resolvedUrl("cava-popout.conf")).replace(/^file:\/\//, ""))

  function close() {
    popoutOpen = false
  }

  function setVolume(v) {
    if (sink && sink.audio) sink.audio.volume = Math.max(0, Math.min(1, v))
  }

  function toggleMute() {
    if (sink && sink.audio) sink.audio.muted = !sink.audio.muted
  }

  // Playback app streams (Spotify, Zen, ...). The live list only feeds the
  // tracker; the Repeater gets snapshots via a timer — rebuilding a Repeater
  // straight off the live PipeWire model on node removal has crashed
  // Quickshell's Pipewire service (see the audio panel's notes).
  readonly property var audioStreams: {
    var list = []
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isStream) continue
      var type = String(n.type || "")
      if (n.isSink !== true && type.indexOf("Stream/Output/Audio") === -1
          && type.indexOf("AudioOutStream") === -1 && type.indexOf("Output") === -1) continue
      if (String(n.name || "").indexOf("omarchy_speaker_tuning") === 0) continue
      if (!n.audio) continue
      list.push(n)
    }
    return list
  }
  property var displayStreams: []

  function refreshStreams() {
    displayStreams = audioStreams.slice()
  }

  onPopoutOpenChanged: {
    if (popoutOpen) refreshStreams()
    else displayStreams = []
  }
  onAudioStreamsChanged: if (popoutOpen) streamsRefreshTimer.restart()

  function streamLabel(node) {
    if (!node) return ""
    var p = node.ready && node.properties ? node.properties : {}
    return p["application.name"] || node.description || p["media.name"] || node.name || ""
  }

  PwObjectTracker {
    objects: root.audioStreams
  }

  Timer {
    id: streamsRefreshTimer
    interval: 75
    onTriggered: root.refreshStreams()
  }

  implicitWidth: barCount * (barWidth + gap) - gap
  implicitHeight: bar ? bar.barSize : 30

  // Latest frame, 0..1 per bar. Reassigned per frame; delegates read by index
  // so the array swap never recreates the Rectangles.
  property var levels: []

  Process {
    id: cava
    command: ["cava", "-p", root.barConfPath]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        var parts = String(line).trim().split(/\s+/)
        if (parts.length < 2) return
        var out = []
        for (var i = 0; i < root.barCount; i++) {
          var v = i < parts.length ? Number(parts[i]) / 1000 : 0
          out.push(v > 1 ? 1 : v)
        }
        root.levels = out
      }
    }
    onExited: if (!root.gone) restarter.restart()
  }

  Timer {
    id: restarter
    interval: 800
    onTriggered: cava.running = true
  }

  Component.onDestruction: {
    root.gone = true
    cava.running = false
  }

  Process {
    id: eqProc
    command: ["easyeffects"]
  }

  // Spectrum for the popout. Crashes while open just freeze it until the
  // popout is toggled; not worth a restart guard for a closed-by-default proc.
  Process {
    id: cavaPopout
    command: ["cava", "-p", root.popoutConfPath]
    running: root.popoutOpen
    stdout: SplitParser {
      onRead: function(line) {
        var parts = String(line).trim().split(/\s+/)
        if (parts.length < 2) return
        var out = []
        for (var i = 0; i < root.popoutBarCount; i++) {
          var v = i < parts.length ? Number(parts[i]) / 1000 : 0
          out.push(v > 1 ? 1 : v)
        }
        root.popLevels = out
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.popoutOpen = !root.popoutOpen
    onWheel: function(wheel) {
      root.setVolume(root.outputVolume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
    }
  }

  Row {
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.gap

    Repeater {
      model: root.barCount

      Rectangle {
        readonly property real level: root.levels.length > index ? root.levels[index] : 0
        width: root.barWidth
        height: Math.max(1, level * root.maxHeight)
        radius: Math.max(1, width / 2)
        color: root.fg
        opacity: 0.92
        anchors.verticalCenter: parent.verticalCenter

        Behavior on height {
          NumberAnimation { duration: 55 }
        }
      }
    }
  }

  PopupCard {
    id: popout
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.popoutOpen
    contentWidth: popout.fittedContentWidth(Style.space(300))
    contentHeight: popout.fittedContentHeight(popoutColumn.implicitHeight)

    Column {
      id: popoutColumn
      anchors.fill: parent
      spacing: Style.space(8)

      Item {
        width: parent.width
        implicitHeight: Math.max(outputHeader.implicitHeight, outputPercent.implicitHeight)

        PanelSectionHeader {
          id: outputHeader
          text: "OUTPUT"
          foreground: root.fg
          fontFamily: root.fontFamily
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: outputPercent
          textFormat: Text.PlainText
          text: Math.round((outputSlider.dragging ? outputSlider.liveValue : root.outputVolume) * 100) + "%"
          color: Qt.darker(root.fg, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          anchors.right: parent.right
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          opacity: root.outputMuted ? 0.5 : 1.0
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.sinkName !== ""
        width: parent.width
        text: root.sinkName
        color: Qt.darker(root.fg, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }

      PanelSlider {
        id: outputSlider
        bar: root.bar
        width: parent.width
        minimum: 0
        maximum: 1
        step: 0.05
        value: root.outputVolume
        opacity: root.outputMuted ? 0.5 : 1.0
        enabled: !!root.sink

        onMoved: function(v) { root.setVolume(v) }
        onRightClicked: root.toggleMute()
      }

      Row {
        spacing: Style.space(6)

        Button {
          text: root.outputMuted ? "Unmute" : "Mute"
          foreground: root.fg
          horizontalPadding: 8
          verticalPadding: 3
          iconSize: Style.font.bodySmall
          fontSize: Style.font.bodySmall
          onClicked: root.toggleMute()
        }

        Button {
          text: "Open Equalizer"
          foreground: root.fg
          horizontalPadding: 8
          verticalPadding: 3
          iconSize: Style.font.bodySmall
          fontSize: Style.font.bodySmall
          onClicked: eqProc.running = true
        }
      }

      // Connected players (output app streams): name, per-app volume, mute.
      PanelSeparator {
        visible: root.displayStreams.length > 0
        foreground: root.fg
      }

      PanelSectionHeader {
        visible: root.displayStreams.length > 0
        text: "STREAMS"
        foreground: root.fg
        fontFamily: root.fontFamily
      }

      Repeater {
        model: root.displayStreams

        delegate: Column {
          id: streamRow
          required property var modelData
          width: parent.width
          spacing: Style.space(2)

          readonly property var node: modelData
          readonly property real streamVolume: node && node.audio ? node.audio.volume : 0
          readonly property bool streamMuted: node && node.audio ? node.audio.muted : false

          Row {
            width: parent.width
            spacing: Style.space(6)

            Text {
              id: streamMuteIcon
              textFormat: Text.PlainText
              text: streamRow.streamMuted ? "󰝟" : "󰕾"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              opacity: streamRow.streamMuted ? 0.5 : 1.0
              anchors.verticalCenter: parent.verticalCenter

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (streamRow.node && streamRow.node.audio)
                  streamRow.node.audio.muted = !streamRow.node.audio.muted
              }
            }

            Text {
              textFormat: Text.PlainText
              text: root.streamLabel(streamRow.node)
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              width: parent.width - streamMuteIcon.width - streamPct.width - Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: streamPct
              textFormat: Text.PlainText
              text: Math.round(streamRow.streamVolume * 100) + "%"
              color: Qt.darker(root.fg, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              opacity: streamRow.streamMuted ? 0.5 : 1.0
            }
          }

          PanelSlider {
            bar: root.bar
            width: parent.width
            minimum: 0
            maximum: 1.5
            step: 0.05
            value: streamRow.streamVolume
            opacity: streamRow.streamMuted ? 0.5 : 1.0

            onMoved: function(v) {
              if (streamRow.node && streamRow.node.audio) streamRow.node.audio.volume = v
            }
            onRightClicked: if (streamRow.node && streamRow.node.audio)
              streamRow.node.audio.muted = !streamRow.node.audio.muted
          }
        }
      }

      PanelSeparator {
        foreground: root.fg
      }

      // EasyEffects-style spectrum: bottom-anchored bars, blue -> green by
      // amplitude (matches EE's own spectrum palette on this theme).
      Item {
        id: spectrum
        width: parent.width
        height: Style.space(96)

        Row {
          anchors.fill: parent
          spacing: 2

          Repeater {
            model: root.popoutBarCount

            Rectangle {
              readonly property real level: root.popLevels.length > index ? root.popLevels[index] : 0
              width: (spectrum.width - (root.popoutBarCount - 1) * 2) / root.popoutBarCount
              height: Math.max(2, level * spectrum.height)
              radius: width / 2
              color: Qt.hsla(0.66 - 0.33 * level, 0.8, 0.55, 1)
              anchors.bottom: parent.bottom

              Behavior on height {
                NumberAnimation { duration: 35 }
              }
            }
          }
        }
      }

    }
  }
}
