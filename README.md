# omarchy-cava-popout

A [cava](https://github.com/karlstav/cava) audio visualizer module for the
[Omarchy](https://omarchy.org) shell's bar, with a click-open popout:

- **Volume slider** for the default sink (drag, wheel; right-click mutes)
- **Per-app volume** — connected players (Spotify, Zen, ...) each get a
  slider + mute under the output controls, with the app's own icon
  (resolved via desktop entries / icon theme)
- **Mute / Open Equalizer** buttons (launches
  [EasyEffects](https://github.com/wwmm/easyeffects) for system-wide EQ)
- **56-bar spectrum analyzer** — a second, denser cava instance that only
  runs while the popout is open
- Scrolling over the bar visualizer adjusts volume without opening the popout

## Requirements

- Omarchy (or any Quickshell setup exposing the `qs.Ui` / `qs.Commons`
  modules and the bar module API)
- `cava`
- `easyeffects` (optional — only for the EQ button)

## Install

Copy the three files into the Omarchy bar modules directory:

```bash
cp cava.qml cava.conf cava-popout.conf ~/.config/omarchy/bar/modules/
```

Install the EQ TUI (optional, needs Python 3.11+):

```bash
install -Dm755 omarchy-eq ~/.local/bin/omarchy-eq
```

Add the module to a bar section in `~/.config/omarchy/shell.json`:

```json
"right": [
  { "id": "cava", "type": "qml" }
]
```

Then restart the shell:

```bash
omarchy restart shell
```

Click the visualizer to open the popout. Tune bar count, framerate and
autosens in `cava.conf` (bar) and `cava-popout.conf` (popout spectrum).

## omarchy-eq TUI

A btop-styled terminal UI for the EasyEffects equalizer, colored from the
current Omarchy theme (`~/.local/state/omarchy/current/theme/colors.toml`),
so wallpaper-derived themes restyle it automatically.

- Live spectrum graph (cava raw output)
- Equalizer band editor: `←/→` select band, `↑/↓` adjust gain, `r` reset
- `n` next preset, `w` write + apply (`easyeffects -l`), `b` bypass, `q` quit

Bands come from `~/.config/easyeffects/presets/output/*.json` — save one
preset from the EasyEffects GUI once to bootstrap. Launch it standalone or
via the popout's **EQ TUI** button (`omarchy-launch-or-focus-tui omarchy-eq`,
same pattern as the system-monitor widget's btop).

## License

[MIT](LICENSE)
