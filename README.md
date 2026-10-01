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

## License

[MIT](LICENSE)
