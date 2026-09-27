// Pure helpers for the Desktop Keybinds panel: JSONC parsing, config
// validation, and turning one config entry into the argv that launches or
// focuses its target.
//
// Kept free of QML imports so tests/keybinds.test.mjs can load it in a Node vm
// the same way the import in KeybindsPanel.qml does.

// The config file is meant to be edited by hand and by AI agents, so it is
// JSONC: `//` and block comments plus trailing commas are accepted. A
// hand-rolled pass beats a regex here because a bare `//` inside a string —
// every URL in this file has one — must survive untouched.
function stripJsonc(raw) {
  var text = raw === null || raw === undefined ? "" : String(raw)
  var out = ""
  var i = 0
  var n = text.length

  while (i < n) {
    var ch = text.charAt(i)

    if (ch === '"') {
      // Copy the literal verbatim, escapes included, until its closing quote.
      out += ch
      i++
      while (i < n) {
        var s = text.charAt(i)
        out += s
        i++
        if (s === "\\") {
          if (i < n) {
            out += text.charAt(i)
            i++
          }
          continue
        }
        if (s === '"') break
      }
      continue
    }

    if (ch === "/" && text.charAt(i + 1) === "/") {
      while (i < n && text.charAt(i) !== "\n") i++
      continue
    }

    if (ch === "/" && text.charAt(i + 1) === "*") {
      i += 2
      while (i < n && !(text.charAt(i) === "*" && text.charAt(i + 1) === "/")) i++
      i += 2
      continue
    }

    out += ch
    i++
  }

  return out.replace(/,(\s*[}\]])/g, "$1")
}

// ------------------------------------------------------------------ scalars

function clampInt(value, fallback, min, max) {
  var n = Number(value)
  if (!isFinite(n)) n = Number(fallback)
  if (!isFinite(n)) n = min
  return Math.max(min, Math.min(max, Math.round(n)))
}

function text(value) {
  if (value === null || value === undefined) return ""
  if (typeof value === "string") return value.trim()
  if (typeof value === "number" || typeof value === "boolean") return String(value)
  return ""
}

// `{plugin}` stands for this plugin's own folder, so a command entry can point
// at something the plugin ships without hardcoding an install path.
function expandTokens(value, pluginDir) {
  var dir = String(pluginDir || "")
  if (!dir) return value
  return value.split("{plugin}").join(dir)
}

// A command may be given as an argv array or as one whitespace-separated
// string. The string form is split naively: no quoting, no globbing, no shell.
function toArgv(value, pluginDir) {
  var out = []
  if (Array.isArray(value)) {
    for (var i = 0; i < value.length; i++) {
      var part = text(value[i])
      if (part) out.push(expandTokens(part, pluginDir))
    }
    return out
  }
  var single = text(value)
  if (!single) return out
  var pieces = single.split(/\s+/)
  for (var j = 0; j < pieces.length; j++) {
    if (pieces[j]) out.push(expandTokens(pieces[j], pluginDir))
  }
  return out
}

// ------------------------------------------------------------------ actions

// Each action becomes a full argv. The three `omarchy-launch-*` wrappers mirror
// the dispatchers Omarchy's own `o.bind` helper builds, so a card row does
// exactly what the matching keybinding would do.
function resolveArgv(raw, pluginDir) {
  var type = text(raw.type) || "app"
  type = type.toLowerCase()

  if (type === "app") {
    var target = text(raw.target)
    if (!target) return null
    // Second argument is the launch command; Omarchy's default for a single
    // word target is `uwsm-app -- <target>`, so target is a safe default.
    return ["omarchy-launch-or-focus", target, text(raw.command) || target]
  }

  if (type === "webapp") {
    var url = text(raw.url)
    if (!url) return null
    // Omarchy focuses a webapp by matching the binding's description against
    // the window title, so the label doubles as the window pattern.
    var pattern = text(raw.target) || text(raw.label)
    if (!pattern) return null
    return ["omarchy-launch-or-focus-webapp", pattern, url]
  }

  if (type === "tui") {
    var tui = toArgv(raw.command !== undefined ? raw.command : raw.target, pluginDir)
    if (!tui.length) return null
    return ["omarchy-launch-or-focus-tui"].concat(tui)
  }

  if (type === "command") {
    var argv = toArgv(raw.command, pluginDir)
    return argv.length ? argv : null
  }

  return null
}

function normalizeShortcut(raw, pluginDir) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null
  var label = text(raw.label)
  var key = text(raw.key)
  if (!label && !key) return null
  var argv = resolveArgv(raw, pluginDir)
  if (!argv) return null
  return { key: key, label: label || key, argv: argv }
}

// ------------------------------------------------------------------- config

var POSITIONS = ["top-left", "top-right", "bottom-left", "bottom-right"]

function emptyConfig(error) {
  return { columns: 2, rowWidth: 248, position: "top-left", shortcuts: [], skipped: 0, error: error || "" }
}

// Never throws: a card with a broken config still has to render, so parse
// problems come back as an error string on an otherwise empty config.
function parseConfig(raw, pluginDir) {
  var stripped = stripJsonc(raw)
  if (!stripped.trim()) return emptyConfig("")

  var parsed
  try {
    parsed = JSON.parse(stripped)
  } catch (e) {
    return emptyConfig(String(e && e.message ? e.message : e))
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return emptyConfig("the top level must be an object")
  }

  var config = emptyConfig("")
  config.columns = clampInt(parsed.columns, 2, 1, 6)
  config.rowWidth = clampInt(parsed.rowWidth, 248, 160, 460)
  if (POSITIONS.indexOf(text(parsed.position)) !== -1) config.position = text(parsed.position)

  var list = Array.isArray(parsed.shortcuts) ? parsed.shortcuts : []
  if (!Array.isArray(parsed.shortcuts)) config.error = '"shortcuts" must be an array'

  for (var i = 0; i < list.length; i++) {
    var entry = normalizeShortcut(list[i], pluginDir)
    if (entry) config.shortcuts.push(entry)
    else config.skipped++
  }

  return config
}
