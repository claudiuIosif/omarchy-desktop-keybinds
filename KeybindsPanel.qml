import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "Keybinds.js" as Keybinds

// Desktop shortcut cheat-sheet: a card listing the user's own app shortcuts,
// anchored to a screen corner behind every window (WlrLayer.Bottom). Clicking a
// row does what the matching keybinding would do. Everything on the card comes
// from a JSONC file the user owns, so the card is a view of their config and
// nothing else.
//
// The card is mounted at boot (keepLoaded), so a config that fails to parse
// must still render: it reports the problem in its footer instead of vanishing.
//
// Panel lifecycle contract (see shell.qml): the shell injects `manifest`
// through the Loader.

Item {
  id: root

  // ---- host injections --------------------------------------------------
  property var manifest: null

  // ---- config ------------------------------------------------------------
  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginId: root.manifest && root.manifest.id
    ? root.manifest.id
    : "io.github.claudiuiosif.desktop-keybinds"
  readonly property string pluginDir: root.home + "/.config/omarchy/plugins/" + root.pluginId
  readonly property string userConfigPath: root.pluginDir + "/shortcuts.jsonc"
  readonly property string exampleConfigPath: root.pluginDir + "/shortcuts.example.jsonc"

  // Two independent readers rather than one that repoints itself: the user file
  // appearing or disappearing mid-session is then just another file change, with
  // no state to get stuck watching the wrong path.
  property bool haveUserConfig: false
  property string userConfigText: ""
  property bool haveExampleConfig: false
  property string exampleConfigText: ""

  readonly property bool usingExample: !root.haveUserConfig
  readonly property var config: Keybinds.parseConfig(
    root.haveUserConfig ? root.userConfigText
      : (root.haveExampleConfig ? root.exampleConfigText : ""),
    root.pluginDir
  )

  // Transient message from an Edit attempt; the next config read clears it.
  property string notice: ""

  FileView {
    id: userConfig
    path: root.userConfigPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.userConfigText = text()
      root.haveUserConfig = true
      root.notice = ""
    }
    onLoadFailed: {
      root.userConfigText = ""
      root.haveUserConfig = false
    }
  }

  FileView {
    id: exampleConfig
    path: root.exampleConfigPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.exampleConfigText = text()
      root.haveExampleConfig = true
    }
    onLoadFailed: {
      root.exampleConfigText = ""
      root.haveExampleConfig = false
    }
  }

  // ---- editing ------------------------------------------------------------
  // The first click on Edit has nothing to open yet, so the shipped example is
  // copied into place first. `cp -n` leaves an existing file alone, which keeps
  // the button idempotent.
  readonly property var editorCandidates: ["nvim", "vim", "micro", "nano", "hx", "code", "gedit"]
  property int editorIndex: 0

  function editConfig() {
    seedConfig.command = ["cp", "-n", root.exampleConfigPath, root.userConfigPath]
    seedConfig.running = false
    seedConfig.running = true
  }

  function openEditor() {
    var fromEnv = Quickshell.env("EDITOR")
    if (fromEnv) {
      launchEditor(fromEnv.split(/\s+/)[0])
      return
    }
    editorIndex = 0
    probeEditor()
  }

  function probeEditor() {
    if (editorIndex >= editorCandidates.length) {
      // No editor to hand the file to, so put the path on the clipboard instead
      // and let the user get there from there.
      notice = "No editor found — config path copied"
      clipboardPath.command = ["wl-copy", root.userConfigPath]
      clipboardPath.running = false
      clipboardPath.running = true
      return
    }
    probeEditorProc.command = ["which", editorCandidates[editorIndex]]
    probeEditorProc.running = false
    probeEditorProc.running = true
  }

  function launchEditor(editor) {
    editTerminal.command = ["omarchy-launch-or-focus-tui", editor, root.userConfigPath]
    editTerminal.running = false
    editTerminal.running = true
  }

  Process {
    id: seedConfig
    onExited: if (exitCode === 0) root.openEditor()
  }

  Process {
    id: probeEditorProc
    onExited: {
      if (exitCode === 0) {
        root.launchEditor(root.editorCandidates[root.editorIndex])
        return
      }
      root.editorIndex++
      root.probeEditor()
    }
  }

  Process {
    id: editTerminal
  }

  Process {
    id: clipboardPath
  }

  // ---- geometry ----------------------------------------------------------
  readonly property bool anchorLeft: config.position === "top-left" || config.position === "bottom-left"
  readonly property bool anchorBottom: config.position === "bottom-left" || config.position === "bottom-right"
  // The top inset clears the bar. The bottom inset assumes the bar is on top,
  // which is where Omarchy puts it.
  readonly property int topMargin: Style.bar.sizeHorizontal + Style.gapsOut
  readonly property int contentWidth: config.rowWidth * config.columns
    + Style.spacing.panelGap * Math.max(0, config.columns - 1)

  // ---- window -------------------------------------------------------------
  PanelWindow {
    id: window
    visible: true
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-keybinds"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {
      x: card.x
      y: card.y
      width: card.width
      height: card.height
    }

    Rectangle {
      id: card
      color: Util.alpha(Color.background, 0.92)
      radius: Style.cornerRadius
      border.width: 1
      border.color: Util.alpha(Color.accent, 0.35)

      width: root.contentWidth + Style.spacing.panelPadding * 2
      height: Style.spacing.panelPadding * 2 + header.height + body.implicitHeight

      // The panel window fills the screen, so the corner is a plain position
      // rather than a set of anchors that would have to be unset conditionally.
      x: root.anchorLeft ? Style.gapsOut : parent.width - width - Style.gapsOut
      y: root.anchorBottom ? parent.height - height - Style.gapsOut : root.topMargin

      // ---- header
      Item {
        id: header
        anchors.top: parent.top
        anchors.topMargin: Style.spacing.panelPadding
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.panelPadding
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.panelPadding
        height: Math.max(titleText.implicitHeight, editButton.height)

        Text {
          id: titleText
          anchors.verticalCenter: parent.verticalCenter
          text: "Shortcuts"
          color: Util.alpha(Color.foreground, 0.75)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }

        Rectangle {
          id: editButton
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          width: editLabel.implicitWidth + Style.spacing.controlPaddingX * 2
          height: Style.spacing.controlHeight
          radius: Math.max(Style.cornerRadius, 6)
          color: editMouse.containsMouse ? Util.alpha(Color.accent, 0.3) : Util.alpha(Color.foreground, 0.08)

          Text {
            id: editLabel
            anchors.centerIn: parent
            text: "Edit"
            color: editMouse.containsMouse ? Color.background : Util.alpha(Color.foreground, 0.8)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          MouseArea {
            id: editMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.editConfig()
          }
        }
      }

      // ---- rows, or a note explaining why there are none, then the footer
      Column {
        id: body
        anchors.top: header.bottom
        anchors.topMargin: Style.spacing.rowGap
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.contentWidth
        spacing: Style.spacing.rowGap

        Grid {
          id: grid
          visible: root.config.shortcuts.length > 0
          width: root.contentWidth
          columns: root.config.columns
          columnSpacing: Style.spacing.panelGap
          rowSpacing: Style.spacing.rowGap

          Repeater {
            model: root.config.shortcuts
            delegate: ShortcutRow {
              entry: modelData
              rowWidth: root.config.rowWidth
            }
          }
        }

        Text {
          id: emptyNote
          visible: root.config.shortcuts.length === 0
          width: root.contentWidth
          horizontalAlignment: Text.AlignHCenter
          text: root.config.error !== "" ? "Config could not be read" : "No shortcuts yet"
          color: Util.alpha(Color.foreground, 0.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          id: footer
          visible: root.footerText !== ""
          width: root.contentWidth
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          color: Util.alpha(Color.foreground, 0.55)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          text: root.footerText
        }
      }
    }
  }

  readonly property string footerText: {
    if (notice !== "") return notice
    if (!haveUserConfig && !haveExampleConfig) return "No config found — reinstall the plugin"
    if (config.error !== "") {
      return usingExample ? "Example config unreadable" : "Config error: " + config.error
    }
    if (config.skipped > 0) return config.skipped + (config.skipped === 1 ? " entry skipped" : " entries skipped")
    if (usingExample) return "Example config — click Edit to make it yours"
    return ""
  }

  // One row: a key badge, a label, and the action. The launcher process lives
  // per instance, so two rows can be clicked in quick succession.
  component ShortcutRow: Item {
    id: srow
    property var entry: null
    property int rowWidth: 248

    readonly property string shortcutKey: entry && entry.key ? String(entry.key) : ""
    readonly property string shortcutLabel: entry && entry.label ? String(entry.label) : ""
    readonly property var shortcutLaunch: entry && entry.argv ? entry.argv : []

    width: rowWidth
    height: 26

    Process {
      id: launchProc
      command: srow.shortcutLaunch
      running: false
    }

    function run() {
      if (!srow.shortcutLaunch || srow.shortcutLaunch.length === 0) return
      launchProc.running = false
      launchProc.running = true
    }

    Rectangle {
      id: rowBg
      anchors.fill: parent
      radius: Math.max(Style.cornerRadius, 6)
      color: m.containsMouse ? Util.alpha(Color.foreground, 0.08) : "transparent"
    }

    Row {
      id: inner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.spacing.xs
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.controlGap

      Rectangle {
        id: keyBadge
        visible: srow.shortcutKey.length > 0
        width: keyText.implicitWidth + Style.spacing.controlPaddingX * 2
        height: 22
        radius: Math.max(Style.cornerRadius, 6)
        color: m.containsMouse ? Util.alpha(Color.accent, 0.35) : Util.alpha(Color.foreground, 0.10)

        Text {
          id: keyText
          anchors.centerIn: parent
          text: srow.shortcutKey
          color: m.containsMouse ? Color.background : Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }

      Text {
        id: labelText
        anchors.verticalCenter: parent.verticalCenter
        // The badge is hidden rather than zero-width when there is no key, so
        // the label has to be told how much room is actually left.
        width: Math.max(0, srow.width
          - (keyBadge.visible ? keyBadge.width : 0)
          - Style.spacing.controlGap
          - Style.spacing.xs * 2)
        text: srow.shortcutLabel
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
    }

    MouseArea {
      id: m
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: srow.run()
    }
  }
}
