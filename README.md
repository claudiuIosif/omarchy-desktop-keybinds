# Desktop Keybinds

A cheat-sheet of your own app shortcuts, pinned to a corner of your desktop
behind every window. Click a row and the app launches, or focuses if it is
already open.

It ships with a commented example config, and the fastest way to fill it in is
to hand it to an AI agent and describe what you actually use.

```
┌────────────────────────────────────────┐
│ Shortcuts                          Edit │
├────────────────────────────────────────┤
│ SUPER+RETURN          Terminal         │
│ SUPER+TAB             Cycle workspaces │
│ SUPER+SHIFT+B         Browser          │
│ SUPER+SHIFT+Y         YouTube          │
│ …                                      │
└────────────────────────────────────────┘
```

## Install

```sh
omarchy plugin add https://github.com/claudiuIosif/omarchy-desktop-keybinds.git --enable
```

The card shows the bundled example until you make it yours, and its footer says
so. To update later:

```sh
omarchy plugin update io.github.claudiuiosif.desktop-keybinds
```

Your own config is never touched by an update.

## Configure it with an AI agent

The config is one JSONC file — comments allowed, trailing commas allowed — and
nothing in it is clever. Which means you do not have to learn the launcher
commands to fill it in. Make your own copy, then give an agent the file and a
list of what you run:

```sh
cp ~/.config/omarchy/plugins/io.github.claudiuiosif.desktop-keybinds/shortcuts.example.jsonc \
   ~/.config/omarchy/plugins/io.github.claudiuiosif.desktop-keybinds/shortcuts.jsonc
```

Or just click **Edit** on the card — it copies the example into place if you do
not have a copy yet, then hands the file to `omarchy-launch-config-editor`. That
is the same path `git` and `sudo` use, so the editor is whatever
`omarchy-default-editor` says it is, and the card reloads the moment you save.
If you have no editor installed at all, the button copies the config path to
your clipboard instead of failing quietly.

Paste this to whichever agent you use:

> I run Omarchy on Linux and installed the "Desktop Keybinds" panel plugin.
>
> Its config is at
> `~/.config/omarchy/plugins/io.github.claudiuiosif.desktop-keybinds/shortcuts.jsonc`.
> If that file does not exist, copy `shortcuts.example.jsonc` from the same
> folder to it first.
>
> Read my `~/.config/hypr/bindings.lua` and my `~/.config/omarchy/shell.json` to
> see what I actually launch and how. Then edit `shortcuts.jsonc` so it has one
> row per app I care about being reminded of.
>
> Rules:
> - Keep the file's existing comments and add to them; do not rewrite them.
> - Only add a row for something I actually use. Ten rows I use beat thirty I
>   don't.
> - For each row, pick `type` from what the app is: an installed application is
>   `"app"`, a website I open in a browser is `"webapp"`, a terminal program is
>   `"tui"`, anything else is `"command"` with an argv array.
> - The `key` field is only a label; the card does not bind anything. If a row's
>   key is not already bound in my `bindings.lua`, tell me the exact `o.bind()`
>   line to add rather than editing that file yourself.
> - Save the file. The card updates on its own.

Most agents will also spot-check with `hyprctl clients -j` (what is running
right now) or `omarchy launch` (what the launcher can start) if a row is
ambiguous.

## Config reference

| Field | Meaning |
| --- | --- |
| `key` | The combination you press. A label only — the card binds nothing. Optional. |
| `label` | What to call the app on the card. Falls back to `key`. |
| `type` | `app` (default), `webapp`, `tui` or `command`. |
| `target` | For `app`: the app name as it appears in a window title. For `webapp`: the window pattern. Defaults to `label`. |
| `url` | For `webapp`: the site to open. |
| `command` | For `app`: the launch command, when it differs from `target` (flatpaks, `uwsm-app -- …`). For `tui` and `command`: the program, as an argv array or one whitespace-separated string. |

```jsonc
{
  "key": "SUPER+SHIFT+S",
  "label": "Stremio",
  "type": "app",
  "target": "stremio",                              // matches the window
  "command": "flatpak run com.stremio.Stremio"      // but launches this
}
```

`{plugin}` expands to the plugin's own folder anywhere in a command, which is
how the bundled script is called. In `command` rows, plain `hyprctl` dispatchers
work too — that is how the "Empty workspace" example jumps to a clean workspace.

A row that cannot be understood is skipped rather than taking the card down; the
footer counts what it dropped, and a config that will not parse is reported
there instead of leaving you with a blank desktop.

### Layout

All optional.

| Field | Default | Range |
| --- | --- | --- |
| `columns` | `2` | 1–6 |
| `rowWidth` | `248` | 160–460 px |
| `position` | `"top-left"` | `top-left`, `top-right`, `bottom-left`, `bottom-right` |

## The workspace-cycle row

The example config includes a row for `SUPER+TAB` that runs
`bin/desktop-keybinds-workspace-cycle`. It walks the workspaces that have
windows and then lands on a clean one, which means it never dead-ends on an
empty screen:

- press it on a clean workspace and you go to the first one with something on it
- press it when every workspace is empty and it still moves you
- press it past the last occupied workspace and it exits the cycle on a clean one
  rather than wrapping back to the start

You do not need a keybinding for it — clicking the row runs it. To also get
`SUPER+TAB`, add this to `~/.config/hypr/bindings.lua`:

```lua
hl.unbind("SUPER + TAB")
o.bind("SUPER + TAB", "Cycle workspaces to empty",
  os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.claudiuiosif.desktop-keybinds/bin/desktop-keybinds-workspace-cycle")
```

## How it behaves

The card is a `WlrLayer.Bottom` layer surface, so windows draw over it and it
takes clicks only on the card itself. It is mounted at shell start rather than
opened from a launcher, which is the point: it is always there, behind
everything.

## Development

```sh
npm test                     # config parsing and normalization
./tests/workspace-cycle.test.sh   # the cycling script's decision table
./tests/lint.sh              # qmllint
```

`Keybinds.js` holds all the parsing and is deliberately free of QML imports, so
the tests load it in a Node vm exactly the way the QML side imports it. The
shell test stubs `hyprctl`, so it never moves your real workspaces.

## Uninstall

```sh
omarchy plugin remove io.github.claudiuiosif.desktop-keybinds
```

Your `shortcuts.jsonc` goes with it, so copy it somewhere first if you want to
keep the list.

## License

MIT
