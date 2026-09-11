# DatasetTracker

`DatasetTracker` ([source](../intan/@DatasetTracker/DatasetTracker.m)) is a
`handle` class that takes a **read-only filesystem inventory** of one directory:
every file the Intan → Kilosort4 pipeline produces or consumes.

Discovery only lists files and decodes JSON. It reads no amplifier data and
parses no `*.rhd` header, so it is cheap. The directory can be a single recording
folder or a parent that contains many recording sub-folders.

The other classes use it so that they share one definition of "a recording",
"a probe map", "a `.bin`" and "a Kilosort4 run":

- `IntanKilosortProject.discover` uses `findRecordingFolders`.
- `IntanDataset.tracker()` / `manifestStruct()` use `latestKilosortRun`.
- The GUI's Probe tab uses `probeMeta` / `readJson`.
- The GUI's Review tab uses `latestKilosortRun`.

## Construction

```matlab
dt = DatasetTracker(folder)                      % scan immediately
dt = DatasetTracker(folder, AutoRefresh=false)   % call dt.refresh() later
dt = DatasetTracker(folder, Recursive=false)     % top level only
dt = DatasetTracker(folder, Name="subj1")
dt = DatasetTracker.fromDataset(ds)              % tracks ds.Folder (not ds.OutputDir)
```

It errors (`DatasetTracker:NoFolder`) if the folder does not exist.
`DatasetTracker()` returns an empty object.

`IntanDataset.tracker()` constructs a tracker of the dataset's `outputFolder()`,
and returns an empty tracker if that folder does not exist yet.
`DatasetTracker.fromDataset(ds)` tracks `ds.Folder`. The two differ when
`OutputDir` is set.

## Properties

| Property | Access | Meaning |
| --- | --- | --- |
| `Root` | public | directory being tracked |
| `Name` | public | defaults to the folder leaf |
| `Recursive` | public | scan sub-folders (default `true`) |
| `Recordings`, `ProbeFiles`, `BinFiles`, `KilosortRuns` | read-only | inventory struct arrays (schemas below) |
| `LastRefreshed` | read-only | time of the last successful scan |
| `NumRecordings`, `NumProbeFiles`, `NumBinFiles`, `NumKilosortRuns`, `NumRhdFiles` | dependent | counts |

The inventory is a **snapshot**. Call `dt.refresh()` after new outputs are
written.

## What counts as each item

### Recordings (`emptyRecordings` schema)

A recording is any folder that **directly** contains at least one `*.rhd` file.
Files are listed in `datenum` order.

| Field | Meaning |
| --- | --- |
| `Name` | folder leaf |
| `Folder` | full path |
| `RhdFiles` | file names |
| `NumRhdFiles` | count |
| `AcqDate` | earliest `datenum` |
| `Bytes` | total `*.rhd` bytes |
| `IsRoot` | the folder is the tracker root |

For split layouts only `info.rhd` is counted, so `Bytes` does not include the
`.dat` files.

### Probe files (`emptyProbes` schema)

Every `*.json` under the root is decoded and classified with `classifyJson`.
Only those classified as `"probe"` are kept.

| Field | Meaning |
| --- | --- |
| `Name`, `Path` | file |
| `NumChannels` | `n_chan`, but never fewer than `numel(chanMap)` |
| `NumShanks` | `numel(unique(kcoords))` |
| `DepthUm` | `max(yc) − min(yc)` |
| `Notes` | optional `notes` field |
| `IsDerived` | file name ends in `_excluded`, i.e. a probe derived by `runKilosort` for channel exclusion |

### Bin files (`emptyBins` schema)

Every `*.bin` is listed. The `<name>.json` sidecar written by
`IntanDataset.toBin` is read when present.

| Field | Meaning |
| --- | --- |
| `Name`, `Path`, `Bytes`, `Modified` | file |
| `SidecarPath` | sidecar path or `""` |
| `NChanBin`, `Fs`, `NSamples`, `SourceFolder` | from the sidecar; `NaN` / `""` when absent |

### Kilosort4 runs (`emptyKSRuns` schema)

A run folder is any folder containing one of `spike_clusters.npy`, `params.py`,
`run_ks4.py`, `settings.json` or `ks4_status.json`.

| Field | Meaning |
| --- | --- |
| `Name`, `Dir` | folder |
| `HasResults` | `spike_clusters.npy` present |
| `State`, `Message` | from `ks4_status.json`. If there is no status file but results exist, `State` is `"done"` |
| `NumUnits` | data rows of `cluster_KSLabel.tsv` (falling back to `cluster_group.tsv`), blank lines excluded; `NaN` if neither file exists |
| `SettingsPath`, `ScriptPath`, `LogPath`, `StatusPath` | paths or `""` |
| `BinFile`, `ProbeFile`, `Fs`, `NChanBin` | from `settings.json` (legacy `runKilosort` engine) |
| `Modified` | newest modification time among the folder's direct files |

For the SpikeInterface engine, the bookkeeping folder (`kilosort4/`, holding
`ks4_status.json`) and the phy output folder (`kilosort4/si/sorter_output/`,
holding `params.py` and `spike_clusters.npy`) show up as **separate** entries in
this inventory. The bookkeeping entry carries the real `State`/`Message`. The
output entry has `HasResults = true`, and because it has no status file of its
own, its `State` is the fallback `"done"`. `latestKilosortRun()` prefers entries
with results, so it returns the output entry. `si_config.json` is not a
recognized marker.

## Methods

| Method | Returns |
| --- | --- |
| `refresh()` | re-scan and rebuild every inventory |
| `ds = recording(idxOrName, AutoMetadata=false)` | an `IntanDataset` for one tracked recording |
| `probeFile(idx)`, `binFile(idx)` | full path of the idx-th item (default 1) |
| `kilosortRun(idx)` | the idx-th run struct |
| `latestKilosortRun()` | most recently modified run, **preferring runs with results**; `[]` if none |
| `hasBin()`, `hasProbe()` | at least one of each found |
| `hasKilosort()` | at least one run has `spike_clusters.npy` |
| `recordingTable()` | table: `Name`, `Folder`, `NumRhdFiles`, `AcqDate`, `SizeMB` |
| `kilosortTable()` | table: `Name`, `State`, `HasResults`, `NumUnits`, `Modified` |
| `disp(dt)` | concise text summary |

Index errors raise `DatasetTracker:BadIndex`. Unknown recording names raise
`DatasetTracker:NoSuchRecording`.

## Static helpers

These are public so the other Intan classes can reuse one implementation.

| Helper | Purpose |
| --- | --- |
| `listFiles(root, pattern, recursive)` | `dir` matches, excluding directories |
| `findRecordings(root, recursive)` | the `Recordings` struct array |
| `findRecordingFolders(root, recursive)` | folder paths only (used by `IntanKilosortProject.discover`) |
| `readJson(path)` | `jsondecode(fileread(path))`, or `[]` on any failure |
| `classifyJson(s)` | see the rules below |
| `probeMeta(s)` | `nChan`, `nShank`, `depth`, `notes` from a decoded probe |
| `emptyRecordings()`, `emptyProbes()`, `emptyBins()`, `emptyKSRuns()` | 0×0 templates that define the schemas |

`classifyJson(s)` applies these rules, most specific first:

1. has `results_dir` and `probe` → `"ks-settings"`
2. has `bin_file` or `source_folder` → `"bin-sidecar"`
3. has `state` → `"ks-status"`
4. has `chanMap`, or has both `xc` and `yc` → `"probe"`
5. otherwise → `"other"`

## Example

```matlab
dt = DatasetTracker("D:\rec\subj1_day1");
disp(dt)
T  = dt.recordingTable();
if dt.hasKilosort
    r = dt.latestKilosortRun();   % r.Dir holds params.py / spike_clusters.npy
end
ds = dt.recording(1, AutoMetadata=true);
```

## Tests

[`test_DatasetTracker.m`](../intan/test_DatasetTracker.m) builds a synthetic tree
(empty `*.rhd` files, a `.bin` + sidecar, a probe `.json` plus a decoy `.json`,
two `kilosort4` folders) and checks recordings, probe classification, bin
sidecars, Kilosort4 runs, accessors/tables, and non-recursive/empty behavior.
(Not run as part of writing this documentation.)
