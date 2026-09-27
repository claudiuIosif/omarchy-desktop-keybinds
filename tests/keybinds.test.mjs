// Runs Keybinds.js in a Node vm the same way the QML side imports it: as a
// plain script whose top-level functions become the module's API.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const source = readFileSync(new URL("../Keybinds.js", import.meta.url), "utf8")
const sandbox = {}
vm.createContext(sandbox)
vm.runInContext(source, sandbox)
const Keybinds = sandbox

const PLUGIN_DIR = "/home/u/.config/omarchy/plugins/io.github.claudiuiosif.desktop-keybinds"

// Arrays built inside the vm belong to that realm, so deepStrictEqual would call
// them unequal to a plain array on this side. Round-tripping the actual value
// through JSON hands back a local one.
const deepEqual = (actual, expected) =>
  assert.deepEqual(JSON.parse(JSON.stringify(actual)), expected)

// ------------------------------------------------------------------ jsonc

test("stripJsonc removes comments but never eats a string", () => {
  assert.equal(Keybinds.stripJsonc('{"a": 1} // trailing'), '{"a": 1} ')
  assert.equal(Keybinds.stripJsonc('{// note\n"a": 1}'), '{\n"a": 1}')
  assert.equal(Keybinds.stripJsonc('{/* note */"a": 1}'), '{"a": 1}')
  // The whole point: every url in a real config has a // in it.
  assert.equal(
    Keybinds.stripJsonc('{ "url": "https://youtube.com/" }'),
    '{ "url": "https://youtube.com/" }'
  )
  assert.equal(
    Keybinds.stripJsonc('{ "note": "a \\" b // c", "url": "http://x" }'),
    '{ "note": "a \\" b // c", "url": "http://x" }'
  )
  // An escaped backslash must not escape the closing quote it precedes.
  assert.equal(Keybinds.stripJsonc('{ "a": "x\\\\", "b": 1 }'), '{ "a": "x\\\\", "b": 1 }')
  assert.equal(Keybinds.stripJsonc(null), "")
  assert.equal(Keybinds.stripJsonc(undefined), "")
})

test("stripJsonc drops trailing commas", () => {
  assert.equal(Keybinds.stripJsonc('{"a": [1, 2, ], }'), '{"a": [1, 2 ] }')
})

// ------------------------------------------------------------------ tokens

test("toArgv accepts an array or a plain string and expands {plugin}", () => {
  deepEqual(Keybinds.toArgv(["a", "b"], ""), ["a", "b"])
  deepEqual(Keybinds.toArgv("flatpak run com.stremio.Stremio", ""), [
    "flatpak",
    "run",
    "com.stremio.Stremio"
  ])
  deepEqual(Keybinds.toArgv(["{plugin}/bin/run"], PLUGIN_DIR), [`${PLUGIN_DIR}/bin/run`])
  deepEqual(Keybinds.toArgv("{plugin}/bin/run --now", PLUGIN_DIR), [
    `${PLUGIN_DIR}/bin/run`,
    "--now"
  ])
  deepEqual(Keybinds.toArgv(["a", "", null, 7], ""), ["a", "7"])
  deepEqual(Keybinds.toArgv("", ""), [])
  deepEqual(Keybinds.toArgv(null, ""), [])
  // No plugin dir known yet: the token stays put rather than becoming "/bin/run".
  deepEqual(Keybinds.toArgv(["{plugin}/bin/run"], ""), ["{plugin}/bin/run"])
})

// ------------------------------------------------------------------ actions

test("app rows focus by target and default the launch command to it", () => {
  const config = Keybinds.parseConfig(
    JSON.stringify({ shortcuts: [{ key: "SUPER+T", label: "Term", target: "foot" }] }),
    PLUGIN_DIR
  )
  deepEqual(config.shortcuts[0].argv, ["omarchy-launch-or-focus", "foot", "foot"])
})

test("app rows keep an explicit launch command", () => {
  const config = Keybinds.parseConfig(
    JSON.stringify({
      shortcuts: [{ label: "Stremio", target: "stremio", command: "flatpak run com.stremio.Stremio" }]
    }),
    PLUGIN_DIR
  )
  deepEqual(config.shortcuts[0].argv, [
    "omarchy-launch-or-focus",
    "stremio",
    "flatpak run com.stremio.Stremio"
  ])
})

test("webapp rows focus by label, as omarchy's own bindings do", () => {
  const config = Keybinds.parseConfig(
    JSON.stringify({ shortcuts: [{ label: "YouTube", type: "webapp", url: "https://youtube.com/" }] }),
    PLUGIN_DIR
  )
  deepEqual(config.shortcuts[0].argv, [
    "omarchy-launch-or-focus-webapp",
    "YouTube",
    "https://youtube.com/"
  ])
})

test("webapp rows prefer an explicit target over the label", () => {
  const config = Keybinds.parseConfig(
    JSON.stringify({
      shortcuts: [{ label: "Mail", type: "webapp", target: "gmail", url: "https://mail.google.com/" }]
    }),
    PLUGIN_DIR
  )
  assert.equal(config.shortcuts[0].argv[1], "gmail")
})

test("tui rows go through the terminal launcher", () => {
  const config = Keybinds.parseConfig(
    JSON.stringify({ shortcuts: [{ label: "Music", type: "tui", command: "cliamp" }] }),
    PLUGIN_DIR
  )
  deepEqual(config.shortcuts[0].argv, ["omarchy-launch-or-focus-tui", "cliamp"])
})

test("command rows run argv verbatim and expand {plugin}", () => {
  const config = Keybinds.parseConfig(
    JSON.stringify({
      shortcuts: [
        { key: "SUPER+TAB", label: "Cycle", type: "command", command: ["{plugin}/bin/cycle"] },
        {
          key: "SUPER+1",
          label: "Empty",
          type: "command",
          command: ["hyprctl", "dispatch", 'hl.dsp.focus({ workspace = "empty" })']
        }
      ]
    }),
    PLUGIN_DIR
  )
  deepEqual(config.shortcuts[0].argv, [`${PLUGIN_DIR}/bin/cycle`])
  deepEqual(config.shortcuts[1].argv, [
    "hyprctl",
    "dispatch",
    'hl.dsp.focus({ workspace = "empty" })'
  ])
})

test("an unknown type is dropped rather than guessed at", () => {
  const config = Keybinds.parseConfig(
    JSON.stringify({ shortcuts: [{ label: "Nope", type: "teleport", target: "x" }] }),
    PLUGIN_DIR
  )
  assert.equal(config.shortcuts.length, 0)
  assert.equal(config.skipped, 1)
})

// ------------------------------------------------------------------ entries

test("an entry needs a runnable action and something to show", () => {
  const config = Keybinds.parseConfig(
    JSON.stringify({
      shortcuts: [
        { label: "No target" },
        { target: "foot" },
        { label: "Fine", target: "foot" },
        "not an object",
        null,
        { label: "No url", type: "webapp" }
      ]
    }),
    PLUGIN_DIR
  )
  assert.equal(config.shortcuts.length, 1)
  assert.equal(config.skipped, 5)
})

test("a row with only a key falls back to the key as its label", () => {
  const config = Keybinds.parseConfig(
    JSON.stringify({ shortcuts: [{ key: "SUPER+T", target: "foot" }] }),
    PLUGIN_DIR
  )
  assert.equal(config.shortcuts[0].label, "SUPER+T")
})

test("a keyless row keeps an empty badge", () => {
  const config = Keybinds.parseConfig(
    JSON.stringify({ shortcuts: [{ label: "Anything", target: "foot" }] }),
    PLUGIN_DIR
  )
  assert.equal(config.shortcuts[0].key, "")
})

// ------------------------------------------------------------------ config

test("layout knobs are clamped and unknown positions ignored", () => {
  const config = Keybinds.parseConfig(
    JSON.stringify({ columns: 99, rowWidth: 10, position: "middle", shortcuts: [] }),
    PLUGIN_DIR
  )
  assert.equal(config.columns, 6)
  assert.equal(config.rowWidth, 160)
  assert.equal(config.position, "top-left")
})

test("a valid position is kept", () => {
  const config = Keybinds.parseConfig(
    JSON.stringify({ position: "bottom-right", shortcuts: [] }),
    PLUGIN_DIR
  )
  assert.equal(config.position, "bottom-right")
})

test("a broken config comes back as an error, never an exception", () => {
  const config = Keybinds.parseConfig("{ shortcuts: [", PLUGIN_DIR)
  assert.notEqual(config.error, "")
  deepEqual(config.shortcuts, [])
  assert.equal(config.columns, 2)

  assert.notEqual(Keybinds.parseConfig("[]", PLUGIN_DIR).error, "")
  assert.notEqual(Keybinds.parseConfig('"nope"', PLUGIN_DIR).error, "")
  assert.notEqual(Keybinds.parseConfig("42", PLUGIN_DIR).error, "")
})

test("an empty config is not an error", () => {
  for (const raw of ["", "   ", "// just a comment", "/* nothing here */", null]) {
    const config = Keybinds.parseConfig(raw, PLUGIN_DIR)
    assert.equal(config.error, "")
    deepEqual(config.shortcuts, [])
  }
})

test("a non-array shortcuts field is reported", () => {
  const config = Keybinds.parseConfig('{"shortcuts": {"a": 1}}', PLUGIN_DIR)
  assert.equal(config.error, '"shortcuts" must be an array')
  deepEqual(config.shortcuts, [])
})

// ------------------------------------------------------------ example file

test("the shipped example config parses into one runnable row per shortcut", () => {
  const example = readFileSync(new URL("../shortcuts.example.jsonc", import.meta.url), "utf8")
  const config = Keybinds.parseConfig(example, PLUGIN_DIR)

  assert.equal(config.error, "")
  assert.equal(config.skipped, 0)
  assert.ok(config.shortcuts.length >= 10)
  for (const row of config.shortcuts) {
    assert.ok(row.key.length > 0, "every example row shows a key")
    assert.ok(row.label.length > 0, "every example row shows a label")
    assert.ok(row.argv.length > 0, "every example row runs something")
  }

  // The workspace-cycle row is the point of the plugin; make sure the token
  // resolved to a path inside the plugin rather than staying literal.
  const cycle = config.shortcuts.find((row) => row.label === "Cycle workspaces")
  assert.ok(cycle, "example config keeps the workspace-cycle row")
  assert.equal(cycle.argv[0], `${PLUGIN_DIR}/bin/desktop-keybinds-workspace-cycle`)
})
