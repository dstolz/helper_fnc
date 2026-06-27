# Kilosort4 probe maps

This folder stores Kilosort4 probe map `.json` files used by `IntanKilosortApp`
and `IntanDataset.runKilosort`. The app scans this folder (by default) to populate
its probe list, but you can point it at any folder.

## Format

Kilosort4 probe `.json` files have the shape produced by
`kilosort.io.save_probe` / accepted by `kilosort.io.load_probe`:

```json
{
  "chanMap": [0, 1, 2, 3, ...],
  "xc":      [0.0, 0.0, 0.0, ...],
  "yc":      [0.0, 20.0, 40.0, ...],
  "kcoords": [0, 0, 0, ...],
  "n_chan":  32
}
```

- `chanMap` — 0-based channel indices into the `.bin` (length = number of
  recorded/used channels).
- `xc`, `yc` — electrode x/y coordinates in microns (same length as `chanMap`).
- `kcoords` — shank/group index per channel (optional; defaults to all zeros).
- `n_chan` — total channel count. The app reports `n_chan` when present,
  otherwise it falls back to `numel(chanMap)`.

## Channel-count checking

The app does a *simple* check: it compares the probe's channel count
(`n_chan`, else `numel(chanMap)`) against the selected dataset's amplifier
channel count (`IntanDataset.NumChannels`). A mismatch is flagged but never
blocks you — Kilosort4 itself will also warn at run time
(`IntanDataset.runKilosort` calls `checkProbeChannels`).

Drop your probe `.json` files in this folder to have them appear automatically.
