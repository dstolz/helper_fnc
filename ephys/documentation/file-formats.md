# Files on disk

This page lists every file the Intan classes read or write, where it lives, and
its schema. MATLAB `jsonencode` writes `NaN` as `null`.

## Folder layout

```text
<Folder>/                               raw recording folder
├─ *.rhd                                traditional layout, or
├─ info.rhd + amplifier.dat + ...       one-file-per-signal, or
├─ info.rhd + amp-<native>.dat ...      one-file-per-channel
├─ <Name>_manifest.json                 dataset manifest (written by the GUI / writeManifest)
└─ <Name><Suffix>.mat                   GUI Convert tab output when its Output folder is blank

<outputFolder>/                         = Folder, or OutputDir, or <OutputRoot>/<Name>
├─ <Name>.bin                           IntanDataset.toBin (legacy engine only)
├─ <Name>.json                          .bin sidecar
├─ <Name>_extract.mat                   IntanDataset.toMat default target
└─ kilosort4/                           kilosortDir()
   ├─ si_config.json                    SpikeInterface engine config
   ├─ run_si_ks4.py                     copy of the driver used for this run
   ├─ ks4_run.log                       captured stdout/stderr
   ├─ ks4_status.json                   {"state": "done"|"error", ...}
   ├─ si/                               run_sorter folder, WIPED on every run
   │  └─ sorter_output/                 Kilosort4 phy output (params.py, *.npy, *.tsv)
   │
   │  -- legacy runKilosort engine writes instead, directly in kilosort4/ --
   ├─ settings.json, run_ks4.py
   ├─ <probe>_excluded.json             derived probe when channels are excluded
   └─ params.py, spike_*.npy, templates.npy, cluster_*.tsv, ...
```

The source `*.rhd` / `*.dat` files are only ever read. The dataset manifest is
written **into the raw recording folder**.

---

## Dataset manifest

Path: `<Folder>/<Name>_manifest.json`. Written by `IntanDataset.writeManifest`;
the GUI writes it on scan, probe assignment, exclusion change, and each batch
run/completion.

Schema (placeholders in `<...>`; `null` where a value is `NaN`):

```text
{
  "schema":           "intan-dataset-manifest/1",
  "name":             <dataset Name>,
  "folder":           <recording folder>,
  "recording_format": "traditional" | "one-file-per-signal" | "one-file-per-channel" | "unknown",
  "updated":          <"yyyy-MM-dd HH:mm:ss">,
  "metadata": {
    "fs": <Hz>, "num_channels": <n>, "duration_s": <s>, "num_files": <n>,
    "acq_date": <"yyyy-MM-dd HH:mm:ss" or "">, "files": [<file names>]
  },
  "probe": {
    "file": <probe .json path or "">, "num_channels": <n>, "num_shanks": <n>,
    "depth_um": <max(yc)-min(yc)>, "notes": <string>
  },
  "exclude_channels": <compact list, e.g. "5,17-18", or "">,
  "bin":      { "file": <BinFile path>, "exists": <true|false> },
  "kilosort": { "has_results": <bool>, "results_dir": <path or "">,
                "num_units": <n or null>, "state": <string> },
  "engine":   "spikeinterface",
  "preprocessing": { <the dataset's SIConfig fields: Filter, FilterFreqMin,
                      FilterFreqMax, CommonReference, ReferenceOperator,
                      DetectBadChannels, BadChannelMethod, BadChannelAction> }
}
```

- `kilosort` comes from `DatasetTracker.latestKilosortRun()` on the output
  folder. That method prefers folders with `spike_clusters.npy`. For the
  SpikeInterface engine it returns `si/sorter_output`, which has no status file,
  so `state` is the tracker's fallback `"done"` there. The real run state is in
  `kilosort4/ks4_status.json`. See
  [DatasetTracker](DatasetTracker.md#kilosort4-runs-emptyksruns-schema).
- `engine` is always written as `"spikeinterface"`, even when results came from
  `runKilosort`.
- On a GUI scan, only `probe.file` (if it still exists) and `exclude_channels`
  are read back (`applyManifest`). Manual artifact periods, artifact-detector
  settings and SpikeInterface settings are not stored here.

---

## Kilosort4 probe JSON

Stored in [`ephys/intan/probes`](../intan/probes/README.md) by default. This is
the shape `kilosort.io.load_probe` accepts:

```json
{
  "notes":   "optional free text",
  "chanMap": [0, 1, 2, 3],
  "xc":      [0, 0, 0, 0],
  "yc":      [0, 20, 40, 60],
  "kcoords": [0, 0, 0, 0],
  "n_chan":  4
}
```

- `chanMap`: **0-based** channel per site. Throughout the MATLAB code, the
  1-based `.bin` channel of a site is `chanMap + 1`. For how the SpikeInterface
  engine interprets it, see
  [python-drivers.md](python-drivers.md#channel-numbering-caveat).
- `xc`, `yc`: site positions in µm.
- `kcoords`: shank per site. Optional; treated as all zeros when absent.
- `n_chan`: total channels. Every channel-count check in the code uses
  `max(n_chan, numel(chanMap))`, ignoring a missing `n_chan`. An `n_chan`
  smaller than the map length is treated as wrong.
- `notes`: optional. The GUI Probe tab edits it in place with a minimal textual
  replacement, so the rest of the file's formatting is preserved.

---

## `.bin` JSON sidecar

Path: `<outputFolder>/<Name>.json`, next to the `.bin`. Written by
`IntanDataset.toBin` (`WriteMeta=true`). Kilosort4 does not read it.
`runKilosort` reads `n_chan_bin` / `fs` from it, and `DatasetTracker` reads
`n_chan_bin`, `fs`, `n_samples` and `source_folder`.

| Field | Meaning |
| --- | --- |
| `n_chan_bin`, `fs`, `dtype`, `n_samples`, `byte_order`, `scale`, `offset` | what was written |
| `bin_file`, `source_folder` | paths |
| `manual_artifacts` | `[k x 2]` seconds (the `ManualArtifacts` in effect) |
| `n_manual_blanked` | samples zeroed by manual periods |
| `auto_artifacts` | `enabled`, `method`, `threshold`, `rmsWindowMs`, `mergeGapMs`, `minChannels`, `padMs`, `nBlanked`, `fraction`, `pctDuration`, `nIntervals`, `channelCounts` |
| `created` | timestamp |

`matrixToBin` delegates to [`matrix2kilosort`](../matrix2kilosort.m), which
writes its own sidecar. See that function's help for its fields.

---

## `si_config.json`

Path: `<kilosort4>/si_config.json`. Written by
`IntanDataset.runSpikeInterface` and consumed by `run_si_ks4.py`.

Schema (placeholders in `<...>`; all paths use forward slashes):

```text
{
  "schema":           "intan-si-ks4/1",
  "folder":           <recording folder>,
  "recording_format": <RecordingFormat>,
  "files":            [<*.rhd names in order, or ["info.rhd"]>],
  "fs":               <Hz>,
  "n_chan":           <amplifier channels>,
  "probe":            <absolute probe .json path>,
  "exclude_channels": [<0-based positions>],
  "results_dir":      <kilosort4>/si,
  "status_path":      <kilosort4>/ks4_status.json,
  "log_path":         <kilosort4>/ks4_run.log,
  "preprocessing": {
    "filter":              { "enabled": <bool>, "freq_min": <Hz>, "freq_max": <Hz> },
    "common_reference":    { "enabled": <bool>, "operator": "median" | "average" },
    "detect_bad_channels": { "enabled": <bool>, "method": <string>, "action": "remove" | "interpolate" },
    "silence_periods":     { "enabled": <bool>, "periods_s": [[<t0>, <t1>], ...] }
  },
  "ks4": { <Kilosort4 settings from ExtraSettings> }
}
```

- `exclude_channels` are **0-based** positions (`ExcludeChannels − 1`).
- `silence_periods.periods_s` is the merged manual + automatic list from
  `artifactIntervals()`, in recording-relative seconds. This file is the record
  of which periods a run actually silenced.
- `ks4` is the Kilosort4 settings block (the GUI's Kilosort-tab parameters).
  `do_CAR: false` is added when the common reference is enabled and `do_CAR` was
  not set explicitly.

## `settings.json` (legacy `runKilosort` engine)

Path: `<ResultsDir>/settings.json`. Fields: `n_chan_bin`, `fs`, `data_dtype`
(from `ds.Dtype`), `filename` (the `.bin`), `probe` (original or
`_excluded.json` probe), `results_dir`, plus any `ExtraSettings` fields. Paths
use forward slashes.

## `ks4_status.json`

Path: in the run folder. Written by the Python driver when it finishes.

| Engine | Success | Failure |
| --- | --- | --- |
| SpikeInterface | `{"state":"done","num_units":N,"bad_channels":[...],"dropped_params":[...]}` | `{"state":"error","message":"...","traceback":"..."}` |
| legacy | `{"state":"done"}` | `{"state":"error","message":"...","traceback":"..."}` |

Both engines delete a stale status file before launching. The GUI's background
monitor polls this file every 3 s.

## Kilosort4 / phy output read by the GUI

Read by the Review tab (`loadReviewResults`) from the folder that holds
`params.py`:

- Required: `spike_clusters.npy`, `spike_times.npy`, `amplitudes.npy`,
  `templates.npy`.
- Optional: `spike_templates.npy`, `channel_shanks.npy`,
  `channel_positions.npy`, `whitening_mat_inv.npy`, `cluster_KSLabel.tsv` (else
  `cluster_group.tsv`), `cluster_Amplitude.tsv`, `cluster_ContamPct.tsv`.
- Sample rate: `sample_rate` from `params.py`, else `fs` from `settings.json`,
  else **30000 Hz** is assumed silently.

`.npy` files are read with a built-in little-endian reader. No toolbox is
needed.

---

## Derived-signal `.mat` (`IntanDataset.toMat`)

The file holds these variables:

| Variable | Contents |
| --- | --- |
| `Y` | struct with `LFP`, `MUA`, `SPIKE` (`single`, `[nSamples x nChan]`); unrequested fields are `single([])` |
| `events` | struct, one field per digital-input line, `[k x 2]` `[t_on t_off]` seconds |
| `info` | see [intan2matlab.md](intan2matlab.md#outputs) |
| `conversion` | `tool`, `created`, `dataset`, `sourceFolder`, `recordingFormat`, `matFileVersion`, `matlabVersion` |

The data is written as `~<name>.partial.mat` and renamed only after a
warning-free `save()` in which all four variables are confirmed present.

---

## GUI Kilosort configuration JSON

Written by **Kilosort tab → Save config...** (default folder
[`ephys/intan/ks4_configs`](../intan/ks4_configs)) and read by **Load config...**.

| Field | Meaning |
| --- | --- |
| `PythonExe`, `CondaEnv`, `OutputRoot` | connection paths |
| `SIConfig` | SpikeInterface preprocessing (see [IntanDataset](IntanDataset.md#default-spikeinterface-configuration)) |
| `Params` | every Kilosort4 control **as typed**. Text kinds stay strings, e.g. `"tmax": "Infinity"`, `"dmin": ""` |
| `ExtraSettings` | the free-form JSON text block, as a string |

Loading ignores fields it does not know. The checked-in
`ks4_config_H64LP_4x16.json` also has `Scale` and `Dtype`, which the current
loader does not read. Older configs that stored `nblocks`, `Th_universal`,
`Th_learned` or `batch_size` at the top level are still applied.
