# Python drivers

The MATLAB classes never import Python through `pyenv`. They call a Python
executable through `system()`, with the paths double-quoted:

```text
"<PythonExe>" "<script>" <args...>
conda run -n <CondaEnv> "<PythonExe>" "<script>" <args...>     % when CondaEnv is set
```

The scripts below are checked into the repository. The two sorting drivers are
**copied** into each run folder before they are executed, so every run keeps
the exact script it used.

| Script | Called by | Environment needs |
| --- | --- | --- |
| [`run_si_ks4.py`](../intan/@IntanDataset/run_si_ks4.py) | `IntanDataset.runSpikeInterface` (the GUI's Run Kilosort4) | spikeinterface, probeinterface, neo, kilosort, torch |
| [`run_ks4.py`](../intan/@IntanDataset/run_ks4.py) | `IntanDataset.runKilosort` (legacy `.bin` engine) | kilosort, torch |
| [`probe_tool.py`](../intan/@IntanKilosortApp/probe_tool.py) | `IntanKilosortApp.runProbeTool` / `ProbeDesignerApp` | probeinterface |

Versions known to work are listed in [INSTALL.md](../intan/INSTALL.md):
spikeinterface 0.104.5, kilosort 4.1.7, probeinterface 0.3.2, neo 0.14.4,
torch 2.7.1.

---

## `run_si_ks4.py`

Usage: `run_si_ks4.py <si_config.json> [--check]`. The config schema is in
[file-formats.md](file-formats.md#si_configjson).

### Pipeline (`build_pipeline`)

1. **Load.**
   - Split layouts read `<folder>/info.rhd` with
     `spikeinterface.extractors.read_intan`, using the stream whose name
     contains `"amplifier"` (else the first stream).
   - Traditional recordings read every listed `.rhd` that exists and
     `concatenate_recordings` them in the order given (the MATLAB side passes
     `ds.Files`, which is in chronological order).
2. **Unsigned → signed.** If the dtype is unsigned, `unsigned_to_signed` is
   applied (Kilosort4 refuses unsigned input).
3. **Crop.** `tmin`/`tmax` are removed from the `ks4` settings block and applied
   as a `frame_slice`, because the SpikeInterface Kilosort4 wrapper does not
   accept them.
4. **Manual exclusions.** `exclude_channels` (0-based positions) are mapped to
   channel IDs **before** the probe is attached.
5. **Attach the probe** (`build_probe`):
   - The KS4 JSON `xc`/`yc`/`chanMap`/`kcoords` are read, and circular contacts
     of radius 6 µm are created.
   - Each `chanMap` value is matched to the recording channel whose **ID ends in
     that integer** (for example `A-016` → 16).
   - Probe sites whose number is not present in the recording are dropped and
     logged ("disabled at acquisition?").
6. **Bandpass**, if `preprocessing.filter.enabled`: `bandpass_filter(freq_min,
   freq_max)`.
7. **Bad channels.**
   - When `detect_bad_channels.enabled`, `detect_bad_channels(method)` runs on
     the bandpassed recording if one exists, otherwise on a 300 Hz
     `highpass_filter` view.
   - The detections are **unioned** with the manual exclusions.
   - The union is removed (`remove_channels`) or interpolated
     (`interpolate_bad_channels`) according to `action`.
   - If the union covers every channel, nothing is removed and a warning is
     logged.
8. **Common reference**, if enabled: `common_reference(operator,
   reference='global')`.
9. **Silence artifacts**, if `silence_periods.enabled`:
   - Each `[t0 t1]` period is shifted by `−tmin` and converted with
     `round(t·fs)`.
   - The result is clamped to the recording, and periods with `end <= start`
     are dropped.
   - The periods are applied with `silence_periods` (zeros).
   - A small in-process patch of `SilencedPeriodsRecording.__init__` rebuilds
     the structured `periods` array after SpikeInterface's JSON round-trip.

### Sorting

- `ks4_params` keeps only the `ks4` keys that
  `get_default_sorter_params('kilosort4')` accepts. The rest are **dropped** and
  logged.
- `delete_recording_dat` defaults to `False`, so the preprocessed
  `recording.dat` is kept for phy.
- The sorter runs as `run_sorter('kilosort4', rec, folder=results_dir,
  remove_existing_folder=True, verbose=True, **params)`. `results_dir` is
  `<kilosort4>/si` and is **wiped** on every run. MATLAB's bookkeeping files live
  one level up, so they survive.

### Status and dry runs

- Success: `ks4_status.json` = `{"state": "done", "num_units", "bad_channels",
  "dropped_params"}`, and the log line `KILOSORT4_DONE units=N`.
- Failure: `{"state": "error", "message", "traceback"}`, the log line
  `KILOSORT4_ERROR`, and the exception is re-raised.
- `--check` builds the pipeline and the parameter list and prints
  `CHECK OK: ...` without sorting. It does not write `ks4_status.json`. Run it by
  hand in the configured environment:

  ```bat
  "<PythonExe>" "<kilosort4>\run_si_ks4.py" "<kilosort4>\si_config.json" --check
  ```

### Channel-numbering caveat

`build_probe` matches `chanMap` values to channel IDs by their **trailing
integer**, whereas `exclude_channels` and the legacy `.bin` engine use
**positions**. The two agree when native channel numbers equal positions
(0, 1, 2, … with no gaps). They can differ when:

- channels were disabled at acquisition (gaps in the numbering), or
- the recording spans more than one port. `A-000` and `B-000` both end in `0`,
  and the lookup keeps the later one.

---

## `run_ks4.py`

Usage: `run_ks4.py <settings.json>`.

1. Loads the probe with `kilosort.io.load_probe(cfg['probe'])`.
2. Passes every other `settings.json` key (except `probe` and `data_dtype`) as
   Kilosort4 `settings`.
3. Calls `kilosort.run_kilosort(settings, probe, filename, data_dtype,
   results_dir)`.

It writes `ks4_status.json` (`{"state": "done"}` or `{"state": "error",
"message", "traceback"}`) in `results_dir` and prints `KILOSORT4_DONE` /
`KILOSORT4_ERROR`.

---

## `probe_tool.py`

Usage:

```text
probe_tool.py list-library [--tag TAG]
probe_tool.py get-library <manufacturer> <probe_name> <out.json> [--name N] [--notes S] [--wiring w0,w1,...] [--n-chan K]
probe_tool.py generate <spec.json> <out.json>
probe_tool.py describe <in.json>
```

| Subcommand | Output |
| --- | --- |
| `list-library` | prints a JSON array of `{manufacturer, probes}`. If probeinterface lacks the listing helpers, it falls back to `neuronexus`, `cambridgeneurotech` and `plexon` with empty probe lists |
| `get-library` | `probeinterface.get_probe(...)` → KS4 JSON written to `out.json`; prints `{out, n_contacts}` |
| `generate` | the spec `{type, params, name, notes, n_chan, wiring}` is built with `generate_linear_probe`, `generate_multi_columns_probe` or `generate_tetrode` → KS4 JSON; prints `{out, n_contacts}` |
| `describe` | prints positions / shank ids / device channel indices / `n_chan` / notes for a KS4 JSON or a probeinterface JSON |

The conversion to KS4 JSON (`pi_probe_to_ks4`) works as follows:

- `xc`, `yc` are the contact positions, rounded to 4 decimals.
- `kcoords` are the shank ids mapped to integers in first-seen order.
- `chanMap` is the explicit `--wiring` if given, else the probe's
  `device_channel_indices` if present and all ≥ 0, else `0..n−1`.
- `n_chan` defaults to `max(n, max(chanMap)+1)`.

On failure the script prints `PROBE_TOOL_ERROR: ...` and exits 1.
`runProbeTool` raises `IntanKilosortApp:runProbeTool:Failed` on a non-zero exit
or that marker. On success it `jsondecode`s the **last** stdout line that parses
as JSON.
