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
- **Mute / Players / Recorders / EQ GUI** buttons (EQ GUI opens
  [EasyEffects](https://github.com/wwmm/easyeffects) for system-wide EQ)
- **EasyEffects row** — output-preset cycling (`‹` / `›`) and a global
  **Bypass** toggle, driven through the `easyeffects` CLI, since EasyEffects 8
  exposes no live control API (all state lives in preset files)
- **Status readout** — kHz · ms · L/R dB, EasyEffects-statusbar-style,
  bottom-right. kHz/ms come from the playing stream's own `node.rate` /
  `node.latency`, and dB is a live peak of what reaches the sink, which is
  post-EasyEffects — the same signal EasyEffects measures
- **72-bar spectrum analyzer** — a second, denser cava instance that only
  runs while the popout is open
- Scrolling over the bar visualizer adjusts volume without opening the popout

## Requirements

- Omarchy with shell plugin support
- `cava`
- `easyeffects` (optional — only for the EQ controls)
- `pw-metadata` (PipeWire, ships with pipewire) for the kHz/ms idle fallback
- `ffmpeg` (for `astats`, which measures the dB level)

## Install

```bash
omarchy plugin add https://github.com/Theartifact369/omarchy-audio-popout.git --enable --yes
```

The widget lands in the bar's right section. Click the visualizer to open the
popout. Tune bar count, framerate and autosens in `cava.conf` (bar) and
`cava-popout.conf` (popout spectrum) inside the installed plugin directory.

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

## License

[MIT](LICENSE)
