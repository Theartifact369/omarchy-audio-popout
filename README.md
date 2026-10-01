# omarchy-audio-popout

An [Omarchy](https://omarchy.org) bar plugin: a
[cava](https://github.com/karlstav/cava) audio visualizer in the bar, and a
click for the full audio panel.

- **Volume slider** for the default sink (drag, wheel; right-click mutes)
- **Per-app volume** — every connected app stream gets a slider + mute row,
  with the app's own icon (resolved via desktop entries / icon theme)
- **Players / Recorders toggles** — each list gets its own header:
  **PLAYERS** for playback streams (Spotify, Zen, ...), **RECORDING INPUTS**
  for mics and line-ins, **RECORDERS** for the apps currently capturing
  (OBS and friends) — every row has volume + mute
- **Mute / EQ TUI / EQ GUI** buttons (the TUI launches in your terminal via
  `omarchy-launch-or-focus-tui`, the GUI button opens
  [EasyEffects](https://github.com/wwmm/easyeffects) for system-wide EQ)
- **EasyEffects row** — output-preset cycling (`‹` / `›`) and a global
  **Bypass** toggle, driven through the `easyeffects` CLI, since EasyEffects 8
  exposes no live control API (all state lives in preset files)
- **Status readout** — kHz · ms · dB (graph clock via `pw-metadata`, dB from
  sink volume), EasyEffects-statusbar-style, bottom-right
- **72-bar spectrum analyzer** — a second, denser cava instance that only
  runs while the popout is open
- Scrolling over the bar visualizer adjusts volume without opening the popout

## Requirements

- Omarchy with shell plugin support
- `cava`
- `easyeffects` (optional — only for the EQ controls)
- `pw-metadata` (PipeWire, ships with pipewire) for the kHz/ms readout

## Install

```bash
omarchy plugin add https://github.com/Theartifact369/omarchy-audio-popout.git --enable --yes
```

The widget lands in the bar's right section. Click the visualizer to open the
popout. Tune bar count, framerate and autosens in `cava.conf` (bar) and
`cava-popout.conf` (popout spectrum) inside the installed plugin directory.

Install the EQ TUI separately if you want the **EQ TUI** button (needs
Python 3.11+):

```bash
install -Dm755 omarchy-eq ~/.local/bin/omarchy-eq
```

Add the module to a bar section in `~/.config/omarchy/shell.json`:

```json
"right": [
  { "id": "Theartifact369.audio-popout" }
]
```

Then restart the shell:

```bash
omarchy restart shell
```

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
