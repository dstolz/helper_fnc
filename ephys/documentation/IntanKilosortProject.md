# IntanKilosortProject

`IntanKilosortProject` ([source](../intan/@IntanKilosortProject/IntanKilosortProject.m))
is a `handle` class that discovers **many recordings** under one root folder,
wraps each one as an [`IntanDataset`](IntanDataset.md), and runs batch
operations over them. It holds shared configuration (probe, Python/conda, output
root, scale, dtype) and pushes it down into every dataset.

The GUI ([`IntanKilosortApp`](IntanKilosortApp.md)) builds one of these on every
**Scan**.

## Construction

```matlab
P = IntanKilosortProject(root)
P = IntanKilosortProject(root, ProbeFile=..., PythonExe=..., OutputRoot=...)
P = IntanKilosortProject(root, AutoDiscover=false)   % set config, call P.discover() later
```

| Option | Default | Meaning |
| --- | --- | --- |
| `ProbeFile`, `PythonExe`, `CondaEnv` | `""` | pushed to every dataset |
| `OutputRoot` | `""` | when set, each dataset's `OutputDir` = `OutputRoot/<Name>` |
| `Scale` | `1/0.195` | pushed to every dataset |
| `Dtype` | `"int16"` | pushed to every dataset |
| `Manifest` | `[]` | optional shared provenance `Manifest` |
| `AutoDiscover` | `true` | run `discover()` in the constructor |

The constructor errors (`IntanKilosortProject:NoRoot`) if `root` does not exist.
`IntanKilosortProject()` with no arguments returns an empty object.

## Properties

| Property | Meaning |
| --- | --- |
| `Root` | root folder that was scanned |
| `Datasets` | `IntanDataset` row array, one per recording folder |
| `ProbeFile`, `PythonExe`, `CondaEnv`, `OutputRoot`, `Scale`, `Dtype`, `Manifest` | shared defaults |
| `NumDatasets` (dependent) | `numel(Datasets)` |

Changing a shared property after construction does **not** update existing
datasets by itself. Call `pushConfig(d)` for each dataset (or re-`discover()`).

## Methods

**`discover()`** finds every folder under `Root` (recursively) that **directly**
contains at least one `*.rhd` file, using
[`DatasetTracker.findRecordingFolders`](DatasetTracker.md#static-helpers). This
matches traditional recordings and split recordings, since `info.rhd` matches
`*.rhd`. One `IntanDataset` is created per folder with `AutoMetadata=false`
(headers are not parsed yet), and `pushConfig` is applied to each. If nothing
is found, `Datasets` is emptied and a warning is issued
(`IntanKilosortProject:NoData`).

**`pushConfig(d)`** copies `ProbeFile`, `PythonExe`, `CondaEnv`, `Scale`,
`Dtype`, `Manifest`, and (when `OutputRoot` is set) `OutputDir = OutputRoot/<Name>`
into one dataset. This **overwrites** that dataset's `ProbeFile`. The GUI
deliberately avoids calling it after scanning so per-dataset probe assignments
survive.

**`d = dataset(idxOrName)`** returns one dataset by index or by `Name`
(`IntanKilosortProject:NoSuchDataset` if the name is not found).

**`dt = tracker(idxOrName)`** returns `dataset(idxOrName).tracker()`, the
[`DatasetTracker`](DatasetTracker.md) inventory of that dataset's output folder.

**`T = gatherMetadata(Force=false)`** calls `refreshMetadata` on every dataset
whose `Fs` is still `NaN` (or on all of them with `Force=true`). It returns one
table row per dataset with these columns:

- `Name`, `Folder`, `NumFiles`, `NumChannels`, `Fs`, `Duration`, `AcqDate`,
  `ChannelNames`
- `HasProbe`: `ProbeFile` is set and exists
- `BinExists`: `BinFile` exists
- `HasKilosort`: the dataset's tracker has a run with `spike_clusters.npy`

**`infos = toBinAll(Name=Value...)`** calls `toBin` on every dataset, passing
all arguments through to `IntanDataset.toBin`. An error on one dataset is caught,
reported as a warning (`IntanKilosortProject:toBinFailed`), and the batch
continues. Each element of `infos` has `Name`, `info` (the `toBin` struct, or
`[]` on failure) and `error` (`""` on success).

**`results = runKilosortAll(Name=Value...)`** calls the legacy
`IntanDataset.runKilosort` on every dataset with the same error handling
(`IntanKilosortProject:runKilosortFailed`). Each element has `Name`, `result`
and `error`. There is **no** project-level wrapper for `runSpikeInterface`; loop
over `P.Datasets` to use that engine (see below).

## Example

```matlab
P = IntanKilosortProject("D:\experiments", ...
    ProbeFile="C:\src\helper_fnc\ephys\intan\probes\H64LP_4x16lin_probemap.json", ...
    PythonExe="C:\Users\me\miniconda3\envs\kilosort\python.exe", ...
    OutputRoot="D:\sorted");

T = P.gatherMetadata();          % header-only, one row per dataset

% Legacy engine: .bin then Kilosort4
infos   = P.toBinAll();
results = P.runKilosortAll(Wait=false);

% SpikeInterface engine (what the GUI runs): no project wrapper, loop instead
for d = P.Datasets
    d.runSpikeInterface(Wait=false);
end
```
