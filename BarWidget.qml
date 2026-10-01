import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

// Omarchy bar audio popout: cava spectrum in the bar, and a click for the
// full audio panel — sink volume, players, recording inputs and capture
// streams, EasyEffects presets/bypass, spectrum, kHz/ms/dB readout.
// Spawns cava in raw mode (one space-separated line of 0..32767 per frame on
// stdout) and draws the values as animated bars in the theme foreground color.
// Click (or scroll over it) opens a popout: default-sink volume slider, mute,
// an EasyEffects launch button for EQ, and a dense EasyEffects-style spectrum
// analyzer from a second cava instance that only runs while the popout is open.
// ponytail: fixed 20 bars / live bars per Repeater index lookup — no delegate
// churn per frame; upgrade to smoother interpolation/fps only if it flickers.

BarWidget {
  id: root
  moduleName: "Theartifact369.audio-popout"

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
  property int popoutBarCount: 72
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

  // App streams (Spotify, Zen, ...). The live lists only feed the trackers;
  // the Repeater gets snapshots via a timer — rebuilding a Repeater straight
  // off the live PipeWire model on node removal has crashed Quickshell's
  // Pipewire service (see the audio panel's notes).
  property bool showPlayers: true
  property bool showRecorders: false

  function mediaClass(n) {
    var p = n && n.ready && n.properties ? n.properties : {}
    return String(p["media.class"] || "")
  }

  // Direction comes from media.class — PwNode.type is a numeric enum
  // (PwNode.AudioSource etc.), not a string, so don't match on it for streams.
  function isPlayerStream(n) {
    if (!n || n.isStream !== true) return false
    return mediaClass(n).indexOf("Stream/Output") === 0
  }

  function isRecorderStream(n) {
    if (!n || n.isStream !== true || isPlayerStream(n)) return false
    if (String(n.name || "") === "cava") return false // our own spectrum captures
    return mediaClass(n).indexOf("Stream/Input") === 0
  }

  // Recording inputs: hardware mics / line-ins. These are device nodes, not
  // streams, so they carry no media.class — the PwNode enum is all we get.
  readonly property var inputDevices: {
    var list = []
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || n.isStream === true || n.type !== PwNode.AudioSource) continue
      if (String(n.name || "").indexOf("omarchy_speaker_tuning") === 0) continue
      if (!n.audio) continue
      list.push(n)
    }
    return list
  }

  // All app streams in one tracker: nothing else in the shell tracks capture
  // streams, and tracking is what gives the rows live volume control. The
  // players/recorders split happens after this, on media.class.
  readonly property var trackedStreams: {
    var list = []
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isStream) continue
      if (String(n.name || "").indexOf("omarchy_speaker_tuning") === 0) continue
      list.push(n)
    }
    return list
  }

  function appStreams(category) {
    var list = []
    var nodes = root.trackedStreams
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (category === "players" ? !isPlayerStream(n) : !isRecorderStream(n)) continue
      if (!n.audio) continue
      list.push(n)
    }
    return list
  }

  readonly property var playerStreams: appStreams("players")
  readonly property var recorderStreams: appStreams("recorders")
  // One entry per visible list, each with its own header: players, recording
  // inputs (mics / line-ins), then the apps currently capturing.
  property var displaySections: []

  function refreshStreams() {
    var sections = []
    if (showPlayers && playerStreams.length > 0)
      sections.push({ label: "PLAYERS", items: playerStreams.slice() })
    if (showRecorders && inputDevices.length > 0)
      sections.push({ label: "RECORDING INPUTS", items: inputDevices.slice() })
    if (showRecorders && recorderStreams.length > 0)
      sections.push({ label: "RECORDERS", items: recorderStreams.slice() })
    displaySections = sections
  }

  onPopoutOpenChanged: {
    if (popoutOpen) refreshStreams()
    else displaySections = []
  }
  onShowPlayersChanged: if (popoutOpen) refreshStreams()
  onShowRecordersChanged: if (popoutOpen) refreshStreams()
  onPlayerStreamsChanged: if (popoutOpen) streamsRefreshTimer.restart()
  onRecorderStreamsChanged: if (popoutOpen) streamsRefreshTimer.restart()
  onInputDevicesChanged: if (popoutOpen) streamsRefreshTimer.restart()

  PwObjectTracker {
    objects: root.trackedStreams
  }

  // dB/kHz/ms readout, EasyEffects-style. dB is sink volume math; kHz + ms
  // come from pw-metadata's graph clock (rate/quantum), read once per open —
  // switching output devices mid-open shows stale numbers until reopened.
  property real clockRate: 0
  property real clockQuantum: 0
  readonly property string sinkDb: !sink || !sink.audio || sink.audio.muted || outputVolume <= 0.0001
    ? "-∞ dB"
    : (20 * Math.log(outputVolume) / Math.LN10).toFixed(1) + " dB"
  readonly property string clockStats: clockRate > 0
    ? (clockRate / 1000).toFixed(1) + " kHz · "
      + (clockQuantum / clockRate * 1000).toFixed(1) + " ms · " + sinkDb
    : sinkDb

  Process {
    id: pwMeta
    command: ["sh", "-c", "pw-metadata -n settings 2>/dev/null || true"]
    running: root.popoutOpen
    stdout: SplitParser {
      onRead: function(line) {
        var m = String(line).match(/key:'clock\.rate' value:'(\d+)'/)
        if (m) root.clockRate = Number(m[1])
        var q = String(line).match(/key:'clock\.quantum' value:'(\d+)'/)
        if (q) root.clockQuantum = Number(q[1])
      }
    }
  }

  // EasyEffects: EE 8 has no live control API (all state lives in preset
  // files), so its CLI is the whole control surface — -l loads a preset,
  // -b 1/-b 2 set global bypass, -b 3 reads it back. Preset names come from
  // the files themselves; -p prints a list whose format isn't worth parsing.
  property var eePresets: []
  property string eeCurrent: ""
  property bool eeBypassed: false

  function loadPreset(name) {
    if (!name) return
    eePresetProc.command = ["sh", "-c", "easyeffects -l '" + name.replace(/'/g, "'\\''") + "' >/dev/null 2>&1"]
    eePresetProc.running = true
    eeCurrent = name
  }

  function stepPreset(delta) {
    if (eePresets.length === 0) return
    var i = eePresets.indexOf(eeCurrent)
    if (i < 0) i = delta > 0 ? -1 : 0
    loadPreset(eePresets[(i + delta + eePresets.length) % eePresets.length])
  }

  Process {
    id: eeStateProc
    running: root.popoutOpen
    command: ["sh", "-c",
      "easyeffects -s 2>/dev/null | sed 's/^/S:/'"
      + "; easyeffects -b 3 2>/dev/null | sed 's/^/B:/'"
      + "; ls -1 ~/.config/easyeffects/presets/output/ 2>/dev/null | sed 's/^/P:/'"]
    stdout: SplitParser {
      onRead: function(line) {
        var m
        if ((m = String(line).match(/^S:output:\s*(.*)$/))) root.eeCurrent = String(m[1]).trim()
        else if ((m = String(line).match(/^B:(\d+)$/))) root.eeBypassed = m[1] === "1"
        else if ((m = String(line).match(/^P:(.+)\.json$/))) root.eePresets = root.eePresets.concat([String(m[1])])
      }
    }
  }

  Process {
    id: eeBypassProc
    command: ["sh", "-c", "easyeffects --bypass-toggle >/dev/null 2>&1; easyeffects -b 3 2>/dev/null"]
    stdout: SplitParser {
      onRead: function(line) {
        var t = String(line).trim()
        if (t === "1") root.eeBypassed = true
        else if (t === "2") root.eeBypassed = false
      }
    }
  }

  Process {
    id: eePresetProc
  }

  function streamLabel(node) {
    if (!node) return ""
    var p = node.ready && node.properties ? node.properties : {}
    return p["application.name"] || node.description || p["media.name"] || node.name || ""
  }

  function iconUrl(icon) {
    var value = String(icon || "")
    if (!value) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var themed = Quickshell.iconPath(value, true)
    return themed && themed.length > 0 ? themed : ""
  }

  // Stream icon: match the app against desktop entries (id or name) and use
  // the entry's icon (themed name or absolute path, e.g. Zen's), falling back
  // to a themed lookup on the app/node name.
  function streamIcon(node) {
    var p = node && node.ready && node.properties ? node.properties : {}
    var names = []
    if (p["application.name"]) names.push(String(p["application.name"]))
    if (node && node.name) names.push(String(node.name))
    var values = DesktopEntries.applications.values || []
    for (var i = 0; i < names.length; i++) {
      var key = names[i].toLowerCase()
      for (var j = 0; j < values.length; j++) {
        var e = values[j]
        if (String(e.id || "").toLowerCase() === key || String(e.name || "").toLowerCase() === key) {
          var url = iconUrl(e.icon)
          if (url) return url
        }
      }
    }
    for (var k = 0; k < names.length; k++) {
      var themed = Quickshell.iconPath(names[k].toLowerCase(), true)
      if (themed && themed.length > 0) return themed
    }
    return ""
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
    contentWidth: popout.fittedContentWidth(Style.space(460))
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
          text: "Players"
          selected: root.showPlayers
          foreground: root.fg
          horizontalPadding: 8
          verticalPadding: 3
          iconSize: Style.font.bodySmall
          fontSize: Style.font.bodySmall
          onClicked: root.showPlayers = !root.showPlayers
        }

        Button {
          text: "Recorders"
          selected: root.showRecorders
          foreground: root.fg
          horizontalPadding: 8
          verticalPadding: 3
          iconSize: Style.font.bodySmall
          fontSize: Style.font.bodySmall
          onClicked: root.showRecorders = !root.showRecorders
        }

        Button {
          text: "EQ TUI"
          foreground: root.fg
          horizontalPadding: 8
          verticalPadding: 3
          iconSize: Style.font.bodySmall
          fontSize: Style.font.bodySmall
          onClicked: if (root.bar && root.bar.run)
            root.bar.run("omarchy-launch-or-focus-tui omarchy-eq")
        }

        Button {
          text: "EQ GUI"
          foreground: root.fg
          horizontalPadding: 8
          verticalPadding: 3
          iconSize: Style.font.bodySmall
          fontSize: Style.font.bodySmall
          onClicked: eqProc.running = true
        }
      }

      // EasyEffects row: output preset cycling + global bypass (EE's CLI is
      // the only control surface it has).
      Row {
        spacing: Style.space(6)

        Button {
          id: presetPrev
          text: "‹"
          enabled: root.eePresets.length > 0
          foreground: root.fg
          horizontalPadding: 10
          verticalPadding: 3
          iconSize: Style.font.bodySmall
          fontSize: Style.font.bodySmall
          onClicked: root.stepPreset(-1)
        }

        Text {
          width: Style.space(130)
          height: presetPrev.height
          verticalAlignment: Text.AlignVCenter
          textFormat: Text.PlainText
          text: root.eeCurrent || (root.eePresets.length > 0 ? "—" : "no presets")
          color: Qt.darker(root.fg, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }

        Button {
          text: "›"
          enabled: root.eePresets.length > 0
          foreground: root.fg
          horizontalPadding: 10
          verticalPadding: 3
          iconSize: Style.font.bodySmall
          fontSize: Style.font.bodySmall
          onClicked: root.stepPreset(1)
        }

        Button {
          text: "Bypass"
          selected: root.eeBypassed
          foreground: root.fg
          horizontalPadding: 8
          verticalPadding: 3
          iconSize: Style.font.bodySmall
          fontSize: Style.font.bodySmall
          onClicked: root.eeBypassProc.running = true
        }
      }

      // Each list gets its own header, so the inputs you record from and the
      // apps capturing are not one undifferentiated "STREAMS" pile.
      PanelSeparator {
        visible: root.displaySections.length > 0
        foreground: root.fg
      }

      Repeater {
        model: root.displaySections

        delegate: Column {
          required property var modelData
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: modelData.label
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          Repeater {
            model: modelData.items

            delegate: Column {
              id: streamRow
              required property var modelData
              width: parent.width
              spacing: Style.space(2)

              readonly property var node: modelData
              readonly property real streamVolume: node && node.audio ? node.audio.volume : 0
              readonly property bool streamMuted: node && node.audio ? node.audio.muted : false
              readonly property string iconSource: root.streamIcon(node)

              Row {
                width: parent.width
                spacing: Style.space(6)

                // App icon (desktop entry match, themed fallback); falls back to
                // a speaker glyph when neither resolves. Click toggles mute.
                Item {
                  id: streamIconSlot
                  width: Style.space(20)
                  height: Style.space(20)
                  anchors.verticalCenter: parent.verticalCenter
                  opacity: streamRow.streamMuted ? 0.5 : 1.0

                  Image {
                    id: streamIconImage
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: width * Screen.devicePixelRatio
                    sourceSize.height: height * Screen.devicePixelRatio
                    source: streamRow.iconSource
                    asynchronous: true
                    visible: streamRow.iconSource !== "" && status !== Image.Error
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: streamRow.streamMuted ? "󰝟" : "󰕾"
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    visible: !streamIconImage.visible
                  }

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
                  width: parent.width - streamIconSlot.width - streamPct.width - Style.space(12)
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
                  // Fixed width + right alignment: horizontal anchors are
                  // forbidden inside Row (they break the whole Row layout).
                  width: Style.space(36)
                  horizontalAlignment: Text.AlignRight
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
        height: Style.space(128)

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

      // EasyEffects-style status readout, bottom-right: kHz · ms · dB.
      Text {
        textFormat: Text.PlainText
        width: parent.width
        horizontalAlignment: Text.AlignRight
        text: root.clockStats
        color: Qt.darker(root.fg, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

    }
  }
}
