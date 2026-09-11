# IntanKilosortApp

`IntanKilosortApp` ([source](../intan/@IntanKilosortApp/IntanKilosortApp.m)) is
a programmatic `uifigure` GUI (a `handle` class, not an App Designer `.mlapp`).
It is used to:

- scan a folder tree for Intan recordings;
- inspect and plot them;
- assign probe maps and channel exclusions;
- configure artifact silencing and SpikeInterface preprocessing;
- run Kilosort4;
- review the sorted units;
- export LFP / MUA / spike-band `.mat` files.

It is a front end over [`IntanKilosortProject`](IntanKilosortProject.md) and
[`IntanDataset`](IntanDataset.md). Reading, filtering, sorting and conversion all
happen in those classes; the app orchestrates them and shows progress.

Installation (MATLAB, conda environments, GPU) is covered in
[INSTALL.md](../intan/INSTALL.md).

## Launching

```matlab
IntanKilosortApp            % open the window
app = IntanKilosortApp;     % open and keep a handle (app.Project, app.Fig, ...)
```

The constructor builds the UI, restores saved preferences (see
[Preferences](#preferences)), and populates the probe list. Closing the window
stops the background monitor, asks any running conversion to stop, and saves
preferences.

## Window layout

- **Menu bar → Dataset**: one checkable item per scanned dataset. This selects
  the single dataset the **Visualize** tab plots.
- **Tabs**, left to right: **Datasets, Probe, Artifacts, Visualize, Kilosort,
  Review, Convert**.
- **Status bar** (bottom): the left side shows the last action; the right side
  shows a suggested next step. The suggestion comes from project state:
  - nothing scanned → *"Browse to a parent folder and click Scan."*
  - some datasets have no probe → *"Assign a probe on the Probe tab (k/n have
    one)."*
  - every dataset has phy output → *"All datasets sorted - open the Review
    tab..."*
  - otherwise → *"Set up the Kilosort tab, then Run Kilosort4 (k/n sorted)."*

### Which dataset does an action act on?

| Action | Target |
| --- | --- |
| Probe tab: Assign to selected, Exclude channels field | the row **last clicked** in the Datasets table |
| Datasets tab: Open in phy | the row last clicked |
| Visualize: Plot | the dataset checked in the **Dataset menu**. Clicking a Datasets row also checks it there |
| Artifacts: Detect / Preview | the Artifacts tab's own **Dataset** dropdown |
| Review: dataset dropdown | its own list (see the caveat under [Review](#review)) |
| Kilosort: Run Kilosort4, Convert: Convert selected | rows **ticked** in the Datasets table's *Select* column, or **all** datasets when none are ticked |
| Probe: Assign to all datasets | every dataset |

Row lookups go through a hidden `DatasetIdx` column, so sorting the table by a
column header does not change which dataset a row refers to.

## Typical workflow

1. **Datasets**: browse to a parent folder and press **Scan**.
2. **Probe**: select a probe map, then **Assign to all datasets** (or to the
   selected one). Enter any per-recording **Exclude channels**.
3. **Artifacts** (optional): tune the detector and press **Detect / Preview**
   to see what would be silenced.
4. **Visualize** (optional): plot a window and mark manual artifact periods.
5. **Kilosort**: set the Python executable, preprocessing and Kilosort4
   parameters, then press **Run Kilosort4 (selected)**.
6. **Review**: load the results, or open them in phy.
7. **Convert** (independent of steps 2–6): export LFP / MUA / SPIKE `.mat`
   files.

---

## Datasets

Controls:

- **Parent directory** + **Browse...**
- **Scan**
- **Refresh metadata**
- **Open in phy**: enabled only when the last-clicked dataset has a `params.py`
  in its Kilosort4 results folder.

**Scan** does the following:

1. Builds `IntanKilosortProject(root)`. This recursively finds every folder that
   directly contains a `*.rhd` (split recordings are found via their
   `info.rhd`).
2. Pushes the Kilosort-tab Python / conda / output root / SpikeInterface
   settings into every dataset.
3. Parses headers for each dataset, with a progress dialog. **Cancel** stops
   header parsing; datasets not yet parsed keep `NaN` metadata. A dataset whose
   headers fail to parse stays in the table, and a warning
   (`IntanKilosortApp:MetaFailed`) is printed to the MATLAB command window.
4. For every dataset, calls `applyManifest()` (restores the saved probe and
   channel exclusions from `<Folder>/<Name>_manifest.json`) and then
   `writeManifest()`.
5. Fills the table, the Dataset menu and the Artifacts dropdown, and pushes the
   artifact settings to every dataset.

**Refresh metadata** re-parses all headers and rebuilds the table.

Table columns:

| Column | Source |
| --- | --- |
| Select | tick to include in batch actions (ticks are kept across refreshes, matched by name) |
| Name, Acq date, # files, # chan, Fs (Hz), Duration (min), Format | `IntanDataset` metadata |
| Probe | probe file name, or `-` |
| Exclude | `ExcludeChannels` as `1,3,5-8`, or `-` |
| Kilosort | `results` (results folder has `spike_clusters.npy`), `ready` (only `params.py`), or `-` |

## Probe

Probe maps are Kilosort4 probe `.json` files
([format](file-formats.md#kilosort4-probe-json)). The default folder is
[`ephys/intan/probes`](../intan/probes/README.md).

- **Probe folder** + **Browse...** + **Refresh** list every `*.json` in the
  folder (not recursive).
- The **probe table** shows Probe, Ch, Shanks, Depth (µm) and Notes, parsed with
  `DatasetTracker.probeMeta`. Files that are not valid JSON are listed with
  Notes `(invalid JSON)`. The **Notes** cell is editable; edits are written back
  into the file's `notes` field with an in-place text edit.
- **Probe info** shows the file name, `n_chan`, `chanMap` length and shank count,
  plus a channel-count check against the last-clicked dataset:
  - `OK` (green): the counts match.
  - `MISMATCH` (red): they differ. This never blocks anything.
  - When exclusions exist, it also reports *"k excluded -> m sorted"*.
- The **preview plot** shows sites by shank, with excluded sites drawn as gray
  `x`. **Show channel numbers** labels each site with its 1-based `.bin`
  channel (`chanMap + 1`).
- **Design probe from probeinterface (library / generate)...** opens
  [`ProbeDesignerApp`](ProbeDesignerApp.md).
- **Import probe .json into folder...** copies a file into the probe folder,
  asking before overwriting.
- **Edit probe .json...** opens the selected file in the MATLAB editor.
- **Exclude channels**: 1-based channels, e.g. `1,5,32-40`. Committing the field
  applies the list to the **last-clicked** dataset. Entries above that dataset's
  channel count are dropped, and the status line reports how many. The list is
  written to the dataset manifest. How exclusions reach Kilosort4 is described in
  [IntanDataset → Channel exclusions](IntanDataset.md#channel-exclusions).
- **Assign to selected dataset** sets `ProbeFile` on the last-clicked dataset.
- **Assign to all datasets** sets `ProbeFile` on every dataset **and** applies
  the Exclude-channels field to every dataset (trimmed per dataset).

Both assign buttons write each target's manifest and report channel-count
mismatches in the status line.

## Artifacts

This tab configures the automatic artifact detector
([`IntanDataset.detectArtifacts`](IntanDataset.md#artifact-detection-and-blanking))
and previews it.

| Control | Maps to | GUI default |
| --- | --- | --- |
| Dataset | which dataset **Detect / Preview** analyzes | first dataset |
| Method | `ArtifactConfig.Method`: Running RMS, MAD, Absolute microvolts, Common-mode | Running RMS |
| Threshold (SD) | `ArtifactConfig.Threshold` | 9 |
| RMS window (ms) | `ArtifactConfig.RmsWindowMs` (0 = auto, about 1 ms); RMS method only | 1 |
| Stitch gap (ms) | `ArtifactConfig.MergeGapMs` | 0 |
| Pad (ms) | `ArtifactConfig.PadMs` | 0 |
| Min channels | `ArtifactConfig.MinChannels` | 2 |
| High-pass before detecting, High-pass (Hz) | preview only (see caveat) | off, 300 |

Every change is pushed to **every** scanned dataset's `ArtifactConfig` and saved
to preferences.

**Detect / Preview** runs `analyzeArtifacts` over the chosen dataset (streamed,
read-only). It shows a summary and a per-channel table. The summary lists method,
window, gap, pad, duration, blanked samples and percent of duration, interval
count and worst channel; the table lists samples flagged and percent of duration
per channel.

Whether automatic detections are **applied** to a sort is set by the Kilosort
tab's **Silence artifacts** checkbox (`ArtifactConfig.Enabled`).

Caveats:

- The Threshold field is sent as-is for every method. The per-method defaults in
  `detectArtifacts` (MAD 8, 1500 µV for microvolts/common-mode) are **not**
  used by the GUI. Switching to *Absolute microvolts* or *Common-mode* with the
  field still at 9 means a 9 µV threshold, despite the "(SD)" label.
- **High-pass before detecting** affects only this preview. The periods silenced
  at run time come from `artifactIntervals()`, which detects on the broadband
  signal.

## Visualize

This tab shows display-only time-domain plots. The data on disk is never
modified. The dataset comes from the **Dataset** menu.

| Control | Meaning |
| --- | --- |
| File | `(all)` or one `*.rhd` file (traditional layout; ignored for split layouts) |
| Channels | e.g. `1:16` or `1 3 5` (1-based amplifier channels) |
| Start (s), Window (s) | initial view |
| High-pass / Low-pass (Hz) | blank = off; both set = bandpass. Uses `filterContinuous` |
| Filter order | 1–8 |
| Reference | None / Common average (mean) / Common median |
| Detrend | subtract each chunk's mean |
| Plot type | Traces / Heatmap (switchable without re-reading) |
| Trace spacing (µV), Heatmap colors | display |
| Sort channels by probe map | order by shank then depth from the dataset's probe; unmapped channels go last |
| Color channels by shank | color traces by probe shank; unmapped channels share one color |

**Plot** streams the selected data one chunk at a time. For each chunk it keeps
the requested channels, converts to single precision, and applies detrend →
re-reference → filter, **per chunk**. The result is cached in a
[`MultiChannelViewer`](../../plotting/@MultiChannelViewer/MultiChannelViewer.m),
which handles all navigation after that. The mouse and keyboard shortcuts are
printed under the controls.

The cache has a memory budget. Where MATLAB's `memory` function works (Windows),
it is min(2 GB, ⅓ of available array memory). Elsewhere it is 1 GB. It is never
below 250 MB. If the requested span would exceed it, the data is
**peak-decimated** on load. Each bin keeps, per channel, the sample with the
largest absolute value. The status line reports the decimation factor and the
effective sample rate.

**Artifact overlays**:

- **Orange**: automatic detections, computed by running `detectArtifacts` with
  the dataset's `ArtifactConfig` on the **cached display data** (after display
  filtering/referencing, and after decimation if any).
- **Red**: manual periods (`ds.ManualArtifacts`).
- **Mark Artifacts** toggles marking mode. In marking mode, left-drag adds a
  period (`addArtifact`) and a left-click inside a red region removes it.
  **Clear Artifacts** removes all manual periods for the dataset.

Caveats:

- The orange overlay is computed on display-processed and possibly decimated
  data, so it can differ from what `artifactIntervals()` silences at run time
  (broadband, full rate).
- When decimation is active, the samples at the end of each chunk that do not
  fill a whole bin are dropped from the cache. Displayed time (sample index ÷
  effective Fs) therefore falls behind true recording time by up to
  (factor − 1) samples at the original rate **per chunk** after the first. Manual
  periods marked on a decimated multi-chunk view inherit that offset. Without
  decimation there is no such offset.
- Manual periods exist **only in memory**. They are not saved to the manifest or
  to preferences, and are lost on re-scan or when the app closes. The periods a
  run actually used are recorded in that run's `si_config.json`.
- Drawing the regions uses `xregion`, which requires MATLAB R2023a or later.
  [INSTALL.md](../intan/INSTALL.md) states R2021a as the minimum.

## Kilosort

The left panel is the configuration; the right panel runs batches and shows the
log.

Connection fields:

| Field | Meaning |
| --- | --- |
| Python exe | Python executable of the `kilosort` env. Seeded on first launch from `%LOCALAPPDATA%\miniconda3\envs\kilosort\python.exe`, `%USERPROFILE%\miniconda3\...` or `%USERPROFILE%\anaconda3\...` when one exists |
| Conda env | optional. When set, commands run as `conda run -n <env> ...` |
| Output root | optional. Each dataset writes to `<root>/<Name>`; blank = the dataset folder |
| Phy command | blank = `conda run -n phy phy` |

Preprocessing (SpikeInterface) maps to `IntanDataset.SIConfig`
([defaults](IntanDataset.md#default-spikeinterface-configuration)):

| Control | GUI default |
| --- | --- |
| Detect bad channels (auto) | on |
| Action (remove / interpolate) | remove |
| Detector method | coherence+psd |
| **Silence artifacts (manual always; auto-detect when ticked)**: `ArtifactConfig.Enabled` | **on** |
| Common reference (CMR/CAR), Operator | off, median |
| Bandpass filter in SpikeInterface, Filter min/max | off, 300 / 6000 Hz |

Note that the GUI's *Silence artifacts* default (on) differs from
`IntanDataset.defaultArtifactConfig().Enabled` (off). Saved preferences override
both.

**Kilosort4 parameters** are generated from
[`kilosortParamSpec`](../intan/@IntanKilosortApp/kilosortParamSpec.m) in five
groups: Data, Preprocessing, Drift correction, Spike detection, and Clustering &
postproc. The spec defaults include `nblocks` 0 (no drift correction),
`Th_universal` 7, `Th_learned` 8, `batch_size` 120000 and `highpass_cutoff`
300; see the spec file for the full list and tooltips.

Control kinds:

| Kind | Behavior |
| --- | --- |
| int / float / bool | sent as typed |
| `nullable` | blank / `null` / `none` is **omitted**, so Kilosort4 uses its own default |
| `floatinf` | blank / `inf` / `Infinity` is **omitted** |
| `vector` | comma- or space-separated numbers |

**Extra settings (JSON)** is merged last and overrides any named field.
`buildKS4Extra` validates everything before a run; the first unparseable field
aborts the batch with a message. `run_si_ks4.py` then drops any key the
SpikeInterface Kilosort4 wrapper does not accept and logs the list; `tmin`/`tmax`
are applied as a crop instead.

**Save config... / Load config...** write and read a JSON snapshot of this tab
([format](file-formats.md#gui-kilosort-configuration-json)). The default folder
is `ephys/intan/ks4_configs`.

**Batch processing**:

- **Execution**: *Non-blocking (background)* (default) or *Blocking (wait)*.
- **Dry run**: write `si_config.json` + `run_si_ks4.py` without launching.
- **Run Kilosort4 (selected)**:
  1. Saves preferences and pushes paths, SpikeInterface settings and artifact
     settings to every dataset.
  2. Validates the Kilosort4 parameters.
  3. Calls `IntanDataset.runSpikeInterface` for each selected dataset.

  The GUI **always** uses the SpikeInterface engine and writes no `.bin`. Errors
  are logged per dataset and the batch continues. Each dataset's manifest is
  rewritten after its launch.

**Background runs** are handed to a MATLAB `timer` (`IntanKilosortAppMonitor`,
every 3 s). On each tick it:

- appends new whole lines of each run's `ks4_run.log` to the log box (lines
  prefixed with the time and dataset name, with carriage-return progress bars
  collapsed to their last state);
- reads `ks4_status.json` and logs `[done]` or `[error] <message>`;
- rewrites that dataset's manifest and refreshes the Datasets table.

The timer stops when every tracked run has a status file. Closing the app stops
the timer but does not stop Python processes that are already running.

Before launching Python, each dataset's automatic artifact scan (when *Silence
artifacts* is on) runs **in MATLAB, synchronously**, as part of
`runSpikeInterface`. So even a background batch blocks the UI for that scan.

## Review

This tab summarizes a Kilosort4 results folder (the folder holding
`params.py`).

- **Kilosort4 results folder** + **Browse...**: choosing a folder loads it.
  **Load** also accepts the dataset folder or the `kilosort4` folder and searches
  `kilosort4/si/sorter_output`, `si/sorter_output`, `sorter_output` and
  `kilosort4` for `params.py`. It requires `spike_clusters.npy`.
- **Dataset dropdown**: meant to list scanned datasets whose tracker has a run
  with results.
- **Open folder in explorer**, **Open in phy** (`phy template-gui params.py`,
  launched detached in the folder).

What is shown after loading:

- **Summary**: Fs, duration, channels, shanks, unit counts by label
  (good / mua / other), total spikes, mean rate, and units per shank.
- **Units table**: Unit, Label, Shank, PkCh, #Spk, FR (Hz), Amp, Cont%.
  - The label comes from `cluster_KSLabel.tsv`, else `cluster_group.tsv`, else
    `unsorted`.
  - Amp comes from `cluster_Amplitude.tsv`, else the median spike amplitude.
  - Cont% comes from `cluster_ContamPct.tsv`.
  - Clicking a row focuses the plots on that unit; **Show all units** clears the
    focus.
- **Plots**:
  - units per shank (stacked good / mua / other);
  - waveforms (all units' peak channel, or the selected unit's 8 largest
    channels ordered by depth);
  - amplitude vs time;
  - firing rate per unit (colored by shank).

How the numbers are derived (from `loadReviewResults` / `renderReviewPlots`):

- **Firing rate** = spike count ÷ **time of the last spike in the sort**, not
  the recording duration. Rates are therefore slightly overestimated when the
  last spike falls before the end of the recording. The summary's "Duration" is
  the same last-spike time.
- **Waveforms** are templates, not averages of raw spikes. Each unit uses its
  most common template (`spike_templates.npy`), unwhitened with
  `whitening_mat_inv.npy` when present, and multiplied by the unit's median
  spike amplitude. The axis is labeled "a.u.".
- **PkCh** is the 1-based index into the templates' channel dimension (the
  sorted channels), not an Intan channel number. Shank comes from
  `channel_shanks.npy` (0 when absent).
- **Amplitude plots** draw at most 30,000 spikes, chosen at evenly spaced
  indices.
- **Sample rate**: `params.py` `sample_rate`, else `settings.json` `fs`, else
  30000 Hz assumed without a warning.

Caveat: `populateReviewDatasets` (which fills the dataset dropdown) is only
called when a scan finds **no** datasets. After a successful scan the dropdown is
not refreshed and still reads *"(pick folder, or scan first)"*. Use **Browse...**
to choose the results folder.

## Convert

This tab exports derived signals with `IntanDataset.toMat`: the
[`intan2matlab` processing](intan2matlab.md), for any recording layout, one
`.mat` per dataset. It is independent of the Kilosort path.

> The Convert tab's LFP filter controls were being added while this
> documentation was written. This section reflects the code as of that session.

### Output

| Control | Meaning |
| --- | --- |
| Output folder | blank (default) = each dataset's **raw data folder**; a folder given here is created if needed |
| File suffix | the file is `<Name><suffix>.mat` (default `_extract`). Characters `\ / : * ? " < > \|` are rejected |
| MAT version | `-v7.3` (default, any size) or `-v7` (under 2 GB per variable) |
| Overwrite existing output files | off: datasets whose output exists are skipped and logged |

### Signals

The LFP / MUA / SPIKE checkboxes set `dataTypeOut`. Each group's
fields are enabled only when that signal is ticked.

| Group | Controls → option |
| --- | --- |
| LFP | `LFP_Fs` (1000); **High-pass** (off, 1 Hz) and **Low-pass** (off, 300 Hz) → `LFP_bpLoHi`, only when ticked; **Notch** (off, `60`) + **Notch width** (2 Hz) → `LFP_NotchHz` / `LFP_NotchBW` |
| MUA | `MUA_Fs` (2000), Integration (1000 Hz), Bandpass low/high (300 / 5000) |
| SPIKE | Keep original rate (on → `SPIKE_Fs = Inf`), `SPIKE_Fs` (20000, used when that box is off), Bandpass low/high (300 / 5000) |

### Channels

| Control | Maps to |
| --- | --- |
| Label field | `labelField` |
| Keep amp channels | `keepAmpChannels`; blank = all |
| Bad channels: None / Manual list / Auto | `badChannels`: nothing, the list, or `-threshold` (default 3). Auto requires LFP |
| Channel remap | `channelRemap` |

The channel lists accept 1-based integers and ranges, with **order and repeats
kept**. For example `1-4, 8, 12-10` → `[1 2 3 4 8 12 11 10]`. Anything
unparseable is an error, never silently dropped. **Reset to defaults** restores
the table above.

### Running

- The targets table lists every dataset a run would process (ticked rows, or all
  when none are ticked), with its format, output file and a pre-run status:
  `ready`, `exists: will skip`, `exists: will overwrite`, or
  `will skip: no Intan files`. **Refresh list** re-checks it.
- **Convert selected**:
  1. Validates all options first.
  2. Refuses to start if two datasets would write the same file (compared
     case-insensitively).
  3. Calls `toMat` for each dataset.
- The overall and per-step progress bars, the current step and a timestamped
  log are updated from the `toMat` progress callback. The log records the
  options, the sizes and rates written, the event counts per line, and the
  channels interpolated.
- **Cancel** takes effect at the next step boundary (between files, processing
  stages, or before the save). `toMat` writes a `~<name>.partial.mat` and renames
  it only after a warning-free, verified `save()`, so a cancelled or failed
  dataset leaves no complete-looking file. Rows not reached are marked
  `not run (cancelled)`.

---

## Preferences

Preferences are stored with `setpref` / `getpref` under the group
`'IntanKilosortApp'`. They are saved on close and after most changes.

| Key(s) | Contents |
| --- | --- |
| `FigurePosition` | window position/size (clamped to the screen on restore) |
| `RootPath`, `ProbeFolder`, `PhyCmd`, `ReviewFolder` | paths |
| `VizChannels`, `VizDuration`, `VizHighpass`, `VizLowpass`, `VizOrder`, `VizReference`, `VizDetrend`, `VizSpacing` | Visualize options (older `VizCAR` is read for backward compatibility) |
| `ArtMethod`, `ArtThreshold`, `ArtRmsWindowMs`, `ArtMergeGapMs`, `ArtPadMs`, `ArtMinChannels`, `ArtFilter`, `ArtHighpass`, `ArtEnable` | Artifacts tab + Silence artifacts |
| `ExecBlocking` | Kilosort execution mode |
| `KilosortConfig` | the Kilosort tab snapshot (`gatherKilosortConfig`) |
| `ConvertConfig` | the Convert tab snapshot (`gatherConvertConfig`) |

To reset everything: `rmpref('IntanKilosortApp')` (with the app closed).

## What the app writes to disk

| File | When |
| --- | --- |
| `<Folder>/<Name>_manifest.json` | scan, probe assignment, exclusion change, each Kilosort4 launch and background completion |
| `<outputFolder>/kilosort4/{si_config.json, run_si_ks4.py, ks4_run.log, ks4_status.json}` and `kilosort4/si/...` | Run Kilosort4 (dry run writes only the first two) |
| probe `.json` in the probe folder | Import, Designer save, Notes edit |
| Kilosort config JSON | Save config... |
| `.mat` per dataset | Convert |

Raw `*.rhd` / `*.dat` files are only read.

## Scripting against a running app

The handle exposes the live objects, for example:

```matlab
app = IntanKilosortApp;
% ... scan in the GUI ...
P  = app.Project;                 % IntanKilosortProject
ds = P.Datasets(1);               % IntanDataset (probe, exclusions, manual artifacts)
ds.ManualArtifacts                % periods marked on the Visualize tab
app.KSRuns                        % background runs being monitored
```

## Source map

| File | Role |
| --- | --- |
| `IntanKilosortApp.m` | properties, constructor, small inline handlers, status bar, background monitor, dataset menu, Convert/Artifacts/Probe helpers |
| `buildUI.m`, `build*Tab.m` | UI construction |
| `onScan.m`, `refreshDatasetsTable.m`, `onDatasetCellSelection.m`, `onRefreshMetadata.m` | Datasets tab |
| `refreshProbeList.m`, `onProbeSelected.m`, `onImportProbe.m`, `onDesignProbe.m`, `runProbeTool.m`, `onAssignProbe.m`, `onApplyExclude.m`, `probe_tool.py` | Probe tab |
| `onDetectArtifacts.m` | Artifacts tab |
| `onPlotVisualization.m`, `onVizButtonDown/Up.m`, `drawVizArtifacts.m`, `applyVizChannelOrder.m`, `applyVizChannelColor.m` | Visualize tab |
| `kilosortParamSpec.m`, `buildKS4Extra.m`, `gather/applyKilosortConfig.m`, `onSave/LoadConfig.m`, `onRunBatch.m`, `pollKSRuns.m`, `onLaunchPhy.m`, `launchPhy.m` | Kilosort tab and phy |
| `loadReviewResults.m`, `renderReviewPlots.m` | Review tab |
| `onRunConvert.m`, `gather/applyConvertConfig.m` | Convert tab |
| `load/savePreferences.m` | preferences |
