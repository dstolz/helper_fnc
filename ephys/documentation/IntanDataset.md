# IntanDataset

`IntanDataset` ([source](../intan/@IntanDataset/IntanDataset.m)) is a `handle`
class that represents **one recording**: one folder of Intan data recorded
contiguously. It is the core of the Intan pipeline. The project, tracker and GUI
classes all act on recordings through it.

An `IntanDataset` can:

- detect which Intan file layout the folder uses and inventory its files;
- parse header metadata cheaply (no amplifier data read);
- read amplifier data, digital-input events and (optionally) board ADC / aux
  input into memory;
- stream the recording one bounded chunk at a time (for `.bin` writing, artifact
  screening and plotting) so peak memory does not scale with recording length;
- filter, screen for artifacts, and blank artifacts;
- write a Kilosort4 `.bin` file (streaming or in-memory);
- launch Kilosort4, either directly on a `.bin` (`runKilosort`) or through
  SpikeInterface on the raw recording (`runSpikeInterface`, the path the GUI uses);
- derive LFP / MUA / spike-band signals and save them to `.mat` (the
  `intan2matlab` processing);
- keep a JSON manifest of its state in the recording folder.

The source `*.rhd` / `*.dat` files are **never modified**. Every write goes to a
new file: `.bin`, JSON sidecar, manifest, Kilosort4 run folder, or `.mat`.

---

## Supported recording layouts

`IntanDataset.detectFormat(folder)` classifies a folder by checking for these
files, **in this order**. The first match wins.

| `RecordingFormat` | Detected when the folder contains | Amplifier data on disk |
| --- | --- | --- |
| `"one-file-per-signal"` | `amplifier.dat` | `info.rhd` header + `amplifier.dat`, int16, `[nChan x nSamp]` with channel varying fastest |
| `"one-file-per-channel"` | any `amp-*.dat` | `info.rhd` header + one int16 file per channel, `amp-<native name>.dat` |
| `"traditional"` | any `*.rhd` | one or more `*.rhd` files with embedded data blocks |
| `"unknown"` | none of the above | none |

For the two split layouts, `Files` is set to `"info.rhd"`, `NumFiles` is `1`,
and the sample count comes from the `.dat` file size (see `splitLayout`).

### Scaling to microvolts

| Layout | Conversion used |
| --- | --- |
| traditional | `read_Intan_RHD2000_file_modified` output: µV = 0.195 × (uint16 − 32768) |
| split (`*.dat`) | µV = 0.195 × int16 (no 32768 offset) |

Split-layout auxiliary signals (`readSplitAll`, one-file-per-signal only):

| Signal | File | Conversion |
| --- | --- | --- |
| board ADC | `analogin.dat` (uint16) | board mode 1: 152.59e-6 × (raw − 32768) V; mode 13: 312.5e-6 × (raw − 32768) V; otherwise 50.354e-6 × raw V |
| aux input | `auxiliary.dat` (uint16) | 37.4e-6 × raw V, at `Fs/4` |
| digital in | `digitalin.dat` (uint16, packed bits) | bit `native_order` of each enabled line |

For one-file-per-channel recordings, digital inputs are read from
`board-DIN-<native_order, 2 digits>.dat` when **all** those files exist.
Otherwise there are no events. Board ADC and aux are **not** read for that layout
(returned as `[]`).

---

## Construction

```matlab
ds = IntanDataset(folder)                        % discover files + parse headers
ds = IntanDataset(folder, AutoMetadata=false)    % discover files only (cheap)
ds = IntanDataset(folder, ProbeFile=..., PythonExe=..., OutputDir=...)
ds = IntanDataset()                              % empty object (arrays/preallocation)
```

| Option | Default | Meaning |
| --- | --- | --- |
| `AutoMetadata` | `true` | call `refreshMetadata` after file discovery |
| `Name` | folder leaf name | dataset name; used for output file names |
| `ProbeFile` | `""` | Kilosort4 probe `.json` |
| `PythonExe` | `""` | Python executable used to launch Kilosort4 / SpikeInterface |
| `CondaEnv` | `""` | when set, commands are run via `conda run -n <env>` |
| `Scale` | `1/0.195` | multiplier applied before casting when writing `.bin` |
| `Dtype` | `"int16"` | `.bin` sample class |
| `OutputDir` | `""` | output folder; `""` means the recording folder |
| `Manifest` | `[]` | optional `Manifest` object ([tools/Manifest.m](../../tools/Manifest.m)) that receives provenance entries |

The constructor errors (`IntanDataset:NoFolder`) if the folder does not exist.

---

## Properties

### Identity (public)

| Property | Type | Meaning |
| --- | --- | --- |
| `Folder` | string | recording folder |
| `Files` | string row | traditional: every `*.rhd`, sorted by file `datenum` (chronological); split: `"info.rhd"` |
| `Name` | string | dataset name (defaults to the folder leaf) |

### Metadata (read-only, filled by `refreshMetadata`)

| Property | Meaning |
| --- | --- |
| `RecordingFormat` | layout, see the table above |
| `Fs` | amplifier sample rate (Hz) |
| `NumChannels` | amplifier channel count (from the first file) |
| `ChannelNames` / `NativeNames` | amplifier `custom_channel_name` / `native_channel_name` |
| `DigInNames` | digital-input custom names |
| `Duration` | total duration (s) = sum of per-file `recordTime` |
| `AcqDate` | earliest file `datenum` (traditional) or the amplifier `.dat` `datenum` (split) |
| `NumFiles` | number of `*.rhd` files (1 for split layouts) |
| `PerFile` | struct array, one element per file: `name`, `bytesPerBlock`, `numDataBlocks`, `numAmplifierSamples`, `recordTime`, `numAmplifierChannels`, `numBoardDigIn`, `headerBytes`, `datenum`, `partialBlock`, `dataPresent` |

### Configuration (public)

| Property | Default | Meaning |
| --- | --- | --- |
| `ProbeFile` | `""` | Kilosort4 probe `.json`. Validated, never generated by this class |
| `ExcludeChannels` | `[]` | 1-based channels to drop from sorting (see [Channel exclusions](#channel-exclusions)) |
| `PythonExe`, `CondaEnv` | `""` | Python launch configuration |
| `Scale` | `1/0.195` | `.bin` scale factor |
| `Dtype` | `"int16"` | one of `int16`, `uint16`, `int32`, `single`, `float32` |
| `OutputDir` | `""` | output folder (`""` = `Folder`) |
| `Manifest` | empty | optional provenance `Manifest` object |
| `ManualArtifacts` | `zeros(0,2)` | manual artifact periods, `[tStart tEnd]` seconds, recording-relative. **In memory only.** Not saved to the dataset manifest |
| `ArtifactConfig` | `defaultArtifactConfig()` | automatic artifact-detector settings |
| `SIConfig` | `defaultSIConfig()` | SpikeInterface preprocessing settings for `runSpikeInterface` |

### Dependent

| Property | Value |
| --- | --- |
| `BinFile` | `fullfile(outputFolder(), Name + ".bin")` |
| `NumSamples` | `sum([PerFile.numAmplifierSamples])`, or `NaN` before metadata is parsed |

---

## Typical use

```matlab
ds = IntanDataset("D:\rec\subj1_day1");
ds.PerFile                                   % per-file header summary

% --- Kilosort4 via SpikeInterface (what the GUI does) ---
ds.ProbeFile = "C:\src\helper_fnc\ephys\intan\probes\H64LP_4x16lin_probemap.json";
ds.PythonExe = "C:\Users\me\miniconda3\envs\kilosort\python.exe";
ds.ExcludeChannels = [5 17];
res = ds.runSpikeInterface(DryRun=true);     % write si_config.json + script only
res = ds.runSpikeInterface();                % run and wait

% --- Legacy path: write a .bin, then run Kilosort4 on it ---
info = ds.toBin();
res  = ds.runKilosort();

% --- Derived signals (intan2matlab processing) ---
[Y, ev, info] = ds.deriveSignals(dataTypeOut=["LFP" "MUA"]);
out = ds.toMat(File="D:\out\subj1.mat", SignalOptions=struct('dataTypeOut', "LFP"));
```

---

## Methods

### Discovery and metadata

**`discoverFiles()`** detects the layout (`detectFormat`) and fills `Files`,
`NumFiles` and (from file dates) `AcqDate`. It also clears the cached split
layout. The constructor calls it, and so does `refreshMetadata`.

**`refreshMetadata()`** re-runs `discoverFiles`, then:

- **traditional**: parses every `*.rhd` header with the private static
  `parseIntanHeader` (header only, no amplifier matrix allocated). Channel names,
  `Fs` and `NumChannels` come from the first file. Two checks apply to later files:
  - A different amplifier channel count raises
    `IntanDataset:refreshMetadata:ChannelMismatch`, because a flat `.bin`
    cannot represent a mid-recording channel change.
  - A truncated trailing data block warns
    (`IntanDataset:refreshMetadata:PartialBlock`), and only whole blocks are
    counted.
- **split layouts**: parses `info.rhd` and derives the sample count from the
  `.dat` size (`splitLayout`). `PerFile` gets a single entry named `"info.rhd"`.

With no files it warns (`IntanDataset:refreshMetadata:NoFiles`) and returns.

**`L = splitLayout()`** (split layouts only) returns and caches a struct
describing the split recording. Fields: `format`, `folder`, `headerFile`, `Fs`,
`nChan`, `nSamp`, `boardMode`, `ampCustom`, `ampNative`, `digInNames`,
`digInNative`, `digInOrders`, `numADC`, `numAux`, `ampFile` / `ampFiles`,
`timeFile`, `digInFile` / `digInFiles`, `adcFile`, `auxFile`, `ampDatenum`.
`nSamp` is computed as follows:

- one-file-per-signal: `floor(bytes(amplifier.dat) / (2·nChan))`
- one-file-per-channel: `floor(bytes(first amp-*.dat) / 2)`, so only the
  **first** channel file is used for sizing

**`parseIntanHeader(ffn)`** (private, static) is a header-only extraction of the
RHD2000 reader. It returns sample rate, channel counts by type, amplifier and
digital-input names and `native_order`, bytes per data block, samples per block
(60 for file version 1, 128 otherwise), whole-block count, `partialBlock`,
`dataPresent`, board mode and file version. It errors on a wrong magic number or
an unknown channel type.

### Reading data

**`data = readData(Name=Value)`** reads the whole recording into memory. For
traditional recordings, each file is read with `read_Intan_RHD2000_file_modified`
and concatenated in time. Split layouts are delegated to `readSplitAll`, which
returns the same struct.

| Option | Default | Meaning |
| --- | --- | --- |
| `Files` | all | subset/order of `*.rhd` files (ignored for split layouts) |
| `KeepChannels` | all | 1-based amplifier channels to keep |
| `IncludeADC`, `IncludeAux` | `false` | also return board ADC / aux input |
| `Concatenate` | `true` | concatenate files in time (`false` returns per-file cells) |
| `ProgressFcn` | none | called as `ProgressFcn(i, nFiles, fileName)` before each file |
| `Precision` | `"double"` | `"single"` casts each file as read (about half the peak memory) |
| `EventLabelField` | `"custom_channel_name"` | or `"native_channel_name"`; which dig-in name keys `events` |

Output fields: `amplifier` `[nSamples x nChan]` µV; `Fs`; `t` = `(0:n-1)'/Fs`;
`channelNames`; `nativeNames`; `channelOrder`; `events` (one field per dig-in
line, `[k x 2]` `[t_on t_off]` seconds); `digInNames`; `digInNativeNames`;
`boardADC`; `aux`; `auxFs`; `files`; `fileSampleCounts`; `units` (`"microvolts"`);
`source`.

Behavior worth knowing:

- A traditional file with no amplifier data is skipped with a warning
  (`IntanDataset:readData:NoData`).
- The digital-input line count is fixed by the **first** file. Extra lines in
  later files are ignored (the same policy as the original `intan2matlab`).
- Events are contiguous high runs of each line, found with `bwlabel` when the
  Image Processing Toolbox is present or an equivalent `diff` fallback otherwise.
  Onset and offset times are reported as **(1-based sample index) / Fs**. See
  [Time conventions](README.md#time-and-indexing-conventions).
- With `Concatenate=false`, `events` is empty and `t` is `[]`.

**`plan = streamPlan(Files=..., MaxChunkSamples=...)`** returns the list of
chunks to stream. Each element has `kind` (`"rhd"` or `"split"`), `name`,
`file`, `sampleOffset` and `nSamples`.

- traditional: one chunk per `*.rhd` file.
- split: fixed-size sample windows over the `.dat`. The default chunk size is
  `max(round(Fs), floor(2.5e8 / (nChan·8)))` samples, about 250 MB of double
  but never less than about 1 s.

**`X = readChunkUV(chunk)`** reads one `streamPlan` element and returns
`[nSamp x nChan]` double µV with **all** channels in header order. An empty
result means the chunk held no amplifier data.

**`X = readSplitWindow(sampleOffset, nSamp)`** reads a sample window directly
from the split `.dat` file(s). It returns `[nSamp x nChan]` double µV. A short
final window returns only the rows present. For one-file-per-channel, the result
is trimmed to the shortest channel read.

`toBin`, `analyzeArtifacts`, `artifactIntervals` and the GUI's Visualize tab all
use `streamPlan` + `readChunkUV`, so they behave the same across layouts and hold
one chunk in memory at a time.

### Filtering

**`Y = filterContinuous(X, Type=..., Cutoff=..., Order=..., Fs=...)`** applies a
zero-phase Butterworth filter (`butter` + `filtfilt`) column-wise to
`[nSamples x nChan]` data. The result is double.

| Option | Default |
| --- | --- |
| `Type` | `"highpass"` (or `"lowpass"`, `"bandpass"`) |
| `Cutoff` | `300` (scalar for high/low-pass, `[lo hi]` for bandpass) |
| `Order` | `4` |
| `Fs` | `ds.Fs` |

Every cutoff must be below Nyquist. Requires the Signal Processing Toolbox.

### Artifact detection and blanking

**`[mask, intervals, stats] = detectArtifacts(X, Name=Value)`** flags samples
of an in-memory `[nSamples x nChan]` block.

| Method | A sample is flagged on a channel when… |
| --- | --- |
| `"rms"` (default) | the running RMS (window `RmsWindowMs`, default about 1 ms) is more than `Threshold` robust SDs (1.4826 × MAD of the RMS) above that channel's median RMS |
| `"mad"` | \|x − median\| / (1.4826 × MAD) > `Threshold` |
| `"microvolts"` | \|x\| > `Threshold` µV |
| `"commonmode"` | \|mean across channels\| > `Threshold` µV (applies to all channels at once) |

A sample is flagged overall when at least `min(MinChannels, nChan)` channels
exceed at once (ignored for `commonmode`). Flagged runs separated by at most
`MergeGapMs` of clean signal are then stitched together, and finally each run is
padded by `PadMs` on both sides.

- Default `Threshold` when not given: rms 9, mad 8, microvolts/commonmode 1500.
- `stats` fields: `method`, `threshold`, `rmsWindowMs` (actual window after
  rounding), `minChannels`, `mergeGapMs`, `padMs`, `fraction`, `numIntervals`,
  and `channelExceedCounts` (per channel, before the `MinChannels` combination).
- `intervals` are `[k x 2]` seconds computed as (1-based index)/Fs.

**`Y = blankArtifacts(X, mask, Fill=...)`** replaces flagged rows on every
channel. `Fill` is `"zero"` (default), `"hold"` (repeat the last clean sample;
0 if the run starts at row 1) or `"nan"`.

**`summary = analyzeArtifacts(Name=Value)`** streams the whole recording, runs
`detectArtifacts` on each chunk with `ArtifactConfig` (per-call options
override), and accumulates statistics **without writing anything**. The GUI's
Artifacts tab uses it for its preview. Options: `Files`, `ChannelOrder`, the
detection parameters, `Filter` / `FilterType` / `FilterCutoff` / `FilterOrder`
(detect on a filtered view; default off) and `ProgressFcn`. Output fields:
`method`, `threshold`, `rmsWindowMs`, `mergeGapMs`, `minChannels`, `padMs`,
`fs`, `nSamples`, `durationSec`, `nChan`, `channelNames`, `channelCounts`,
`channelPct`, `nBlanked`, `fraction`, `pctDuration`, `nIntervals` (summed per
chunk), `files`.

Detection runs **per chunk**. The robust baseline (median/MAD) is computed within
each chunk, and runs are not stitched across chunk boundaries.

**`iv = artifactIntervals(Name=Value)`** returns the merged `[k x 2]` list of
periods (seconds) that `runSpikeInterface` passes to SpikeInterface
`silence_periods`:

- all `ManualArtifacts` (always included), plus
- automatic intervals from the same chunked detector, when
  `ArtifactConfig.Enabled` is true (or `IncludeAuto=true`). Each chunk's intervals
  are shifted by the running sample offset.

Overlapping or touching periods are merged. Periods with `tEnd <= tStart` are
**dropped**, which includes an automatic detection only one sample long. By
default it detects on the broadband signal (`Filter=false`).

#### Manual periods

- `addArtifact(t0, t1)` appends `[t0 t1]` (seconds, recording-relative),
  clamps negatives to 0, ignores zero-width periods, then sorts and merges
  overlaps.
- `mask = manualArtifactMask(nSamp, sampleOffset, Fs)` returns the per-block
  logical mask `toBin` uses. It covers samples `ceil(t0·Fs) … floor(t1·Fs)` as
  0-based absolute indices.

#### Default artifact configuration

`IntanDataset.defaultArtifactConfig()`:

| Field | Default | Meaning |
| --- | --- | --- |
| `Enabled` | `false` | `toBin` blanks, and `artifactIntervals` includes auto detections, only when true |
| `Method` | `"rms"` | detector method |
| `Threshold` | `9` | robust SDs (µV for microvolts/commonmode) |
| `RmsWindowMs` | `NaN` | running-RMS window, ms; `NaN` = about 1 ms |
| `MergeGapMs` | `0` | stitch gaps up to this length |
| `MinChannels` | `2` | channels that must exceed simultaneously |
| `PadMs` | `0` | expand each run by this much on both sides |

`normalizeArtifactConfig(cfg)` fills missing fields from these defaults and
drops unknown fields.

### Writing a Kilosort4 `.bin`

**`info = toBin(Name=Value)`** streams the recording to `BinFile` (or `BinFile=`
override). The file has no header, is little-endian, and has the channel index
varying fastest. It holds one chunk in memory at a time. Per chunk, in order:

1. read µV (`readChunkUV`);
2. check the channel count (error `IntanDataset:toBin:ChannelMismatch` if it
   changes);
3. reorder/subset (`ChannelOrder`);
4. filter, if `Filter=true` (default **off**; Kilosort4 filters internally);
5. auto-detect and zero artifacts, if `Blank=true` **or**
   `ArtifactConfig.Enabled`;
6. zero `ManualArtifacts` (mapped with the running sample offset);
7. compute `scale × x + Offset`, count out-of-range samples, cast, write.

| Option | Default |
| --- | --- |
| `Files`, `ChannelOrder` | all |
| `Scale` / `Dtype` | `ds.Scale` / `ds.Dtype` |
| `Offset` | `0` |
| `Filter`, `FilterType`, `FilterCutoff`, `FilterOrder` | off, `"highpass"`, `300`, `4` |
| `FilterEdgeMode` | `"independent"` (each chunk filtered on its own). `"overlap"` prepends the previous chunk's last `OverlapSamples` raw samples before filtering |
| `Blank`, `ArtifactMethod`, `ArtifactThreshold`, `ArtifactRmsWindowMs`, `ArtifactMergeGapMs`, `ArtifactMinChannels`, `ArtifactPadMs` | fall back to `ArtifactConfig` |
| `WriteMeta` | `true` (writes a `<name>.json` sidecar next to the `.bin`) |
| `BinFile` | `ds.BinFile` |

With the default scale `1/0.195`, µV are converted back to native int16 ADC
units. For integer dtypes, values outside the class range are **clipped** by the
cast. Clipping is counted (`info.nClipped`) and reported by a warning
(`IntanDataset:toBin:Clipping`).

`info` fields: `filename`, `dtype`, `nChan`, `nSamples`, `fs`, `scale`,
`offset`, `byteOrder`, `nClipped`, `nManualArtifacts`, `nManualBlanked`,
`nAutoBlanked`, `autoArtifact` (settings used + `nBlanked`, `fraction`,
`pctDuration`, `nIntervals`, `channelCounts`), `nBytes`, `metaFile`. The sidecar
schema is in [file-formats.md](file-formats.md#bin-json-sidecar).

**`info = matrixToBin(X, Name=Value)`** writes an in-memory
`[nSamples x nChan]` µV matrix by delegating to
[`matrix2kilosort`](../matrix2kilosort.m), using the dataset's
`Scale`/`Dtype`/`Fs`. Options: `BinFile`, `Scale`, `Offset`, `Dtype`, `Fs`,
`ChannelOrder`, `ChannelsAreRows`, `WriteMeta`. The code comments state that,
for the same data and options, it produces a file byte-identical to `toBin`;
`test_IntanDataset` section 4 checks this.

### Running Kilosort4

There are two engines. The GUI uses **`runSpikeInterface`**. `runKilosort` is
the older `.bin`-based path, kept for scripting and batch use
(`IntanKilosortProject.runKilosortAll`).

Both launch Python through `system()` (not MATLAB's `pyenv`) as either
`"<PythonExe>" "<script>" "<config>"` or
`conda run -n <CondaEnv> "<PythonExe>" "<script>" "<config>"`. Both:

- copy the checked-in driver script into the run folder;
- delete any stale `ks4_status.json` before launching;
- support blocking (`Wait=true`, default) or detached background (`Wait=false`)
  execution.

In blocking mode, output is captured and written to `ks4_run.log` after the
process exits. In background mode, output is redirected to `ks4_run.log` with
`PYTHONUNBUFFERED=1`, and `result.status` is the **launcher's** status, not
Kilosort4's exit code. Either way the Python script writes `ks4_status.json`
(`state` `"done"` or `"error"`) when it finishes.

#### `result = runSpikeInterface(Name=Value)`

This path writes no `.bin`. It writes `si_config.json` and a copy of
[`run_si_ks4.py`](../intan/@IntanDataset/run_si_ks4.py) into `kilosortDir()`
(`<outputFolder>/kilosort4`) and runs it. The script reads the raw recording with
SpikeInterface, attaches the probe, applies the `SIConfig` preprocessing plus
artifact silencing, and runs Kilosort4 via `run_sorter` into `<kilosort4>/si`.
Kilosort4's phy files end up in `<kilosort4>/si/sorter_output`. The pipeline is
described step by step in [python-drivers.md](python-drivers.md#run_si_ks4py).

| Option | Default |
| --- | --- |
| `PythonExe`, `CondaEnv`, `ProbeFile` | dataset properties |
| `ExcludeChannels` | `ds.ExcludeChannels` |
| `ResultsDir` | `kilosortDir()` |
| `Fs`, `NChan` | `ds.Fs`, `ds.NumChannels` |
| `SIConfig` | `ds.SIConfig` |
| `ExtraSettings` | `struct()`: Kilosort4 settings passed to `run_sorter` |
| `ArtifactIntervals` | computed by `artifactIntervals()` |
| `Files` | `ds.Files` |
| `DryRun` | `false`: write config + script and build the command without launching |
| `Wait` | `true` |

- If `SIConfig.CommonReference` is on and `ExtraSettings` has no `do_CAR`,
  `do_CAR=false` is added so Kilosort4 does not re-reference.
- Computing `ArtifactIntervals` with `ArtifactConfig.Enabled` scans the **whole
  recording in MATLAB** before Python is launched, even for a background run.
- `result` fields: `status`, `command`, `stdoutLog`, `scriptPath`,
  `settingsPath` (the `si_config.json`), `resultsDir` and `runDir` (both the
  `kilosort4` folder), `sorterDir`, `probeFile`, `excludeChannels`, `dryRun`,
  `wait`, `statusFile`, `background`.

#### Default SpikeInterface configuration

`IntanDataset.defaultSIConfig()` (the fields map to `si_config.json`
`preprocessing`):

| Field | Default | Meaning |
| --- | --- | --- |
| `Filter` | `false` | `bandpass_filter` before sorting (off: Kilosort4 high-passes internally) |
| `FilterFreqMin` / `FilterFreqMax` | `300` / `6000` Hz | band edges |
| `CommonReference` | `false` | global `common_reference` |
| `ReferenceOperator` | `"median"` | or `"average"` |
| `DetectBadChannels` | `true` | run `detect_bad_channels` |
| `BadChannelMethod` | `"coherence+psd"` | also `"std"`, `"mad"`, `"neighborhood_r2"` |
| `BadChannelAction` | `"remove"` | or `"interpolate"` |

`normalizeSIConfig(cfg)` fills missing fields and drops unknown ones.

#### `result = runKilosort(Name=Value)` (legacy `.bin` engine)

This requires an existing `.bin` (run `toBin` first) unless `DryRun=true`. It
writes `settings.json` and a copy of
[`run_ks4.py`](../intan/@IntanDataset/run_ks4.py) into `ResultsDir` (default
`<outputFolder>/kilosort4`), then calls `kilosort.run_kilosort`. The phy output
lands directly in that folder.

- `n_chan_bin` and `fs` resolve in this order: options, then the `.bin` JSON
  sidecar, then `NumChannels`/`Fs`.
- `data_dtype` in `settings.json` is `ds.Dtype`. If you wrote the `.bin` with a
  `Dtype=` override, pass a matching dataset `Dtype`.
- The probe channel count is compared with `n_chan_bin`. A mismatch only warns
  (`IntanDataset:runKilosort:ProbeChannelMismatch`).
- Options: `PythonExe`, `CondaEnv`, `ProbeFile`, `ExcludeChannels`, `BinFile`,
  `ResultsDir`, `NChanBin`, `Fs`, `ExtraSettings` (merged into `settings.json`),
  `DryRun`, `Wait`.
- `result` fields: `status`, `command`, `stdoutLog`, `scriptPath`,
  `settingsPath`, `resultsDir`, `binFile`, `probeFile`, `excludeChannels`,
  `nExcludedChannels`, `dryRun`, `wait`, `statusFile`, `background`.

#### Channel exclusions

`ExcludeChannels` holds 1-based indices of the recording's amplifier channels
(the `.bin` row order). How they are applied depends on the engine:

- **`runKilosort`** writes `<probe>_excluded.json` into the results folder with
  every probe site whose `chanMap + 1` is in the list removed from `chanMap`,
  `xc`, `yc` and `kcoords`. `n_chan` is unchanged, the channels stay in the
  `.bin`, and the original probe file is not modified.
- **`runSpikeInterface`** passes them as 0-based positions (`exclude_channels`)
  to `run_si_ks4.py`. The script **unions** them with the automatically detected
  bad channels and applies `SIConfig.BadChannelAction` to all of them. So with
  `"interpolate"`, manually excluded channels are interpolated, not removed. If
  the union covers every channel, nothing is removed and a warning is logged.

#### Locating results

- `kilosortDir()` returns `<outputFolder>/kilosort4`, where both engines write
  their bookkeeping.
- `kilosortResultsDir()` returns the first of these that contains `params.py`:
  `<kilosort4>/si/sorter_output`, `<kilosort4>/sorter_output`, `<kilosort4>`.
  If none does, it returns `kilosortDir()`.
- `hasPhyOutput()` is true when that folder has `params.py`.
- `hasKilosortResults()` is true when it has `spike_clusters.npy`.

### Derived signals (the `intan2matlab` processing)

> These two methods were being edited while this documentation was written. The
> description below reflects the code as of the documentation date; check the
> source header if in doubt.

**`[Y, ev, info] = deriveSignals(Name=Value)`** reads the whole recording through
`readData` (single precision; any layout) and derives the requested signals.
`intan2matlab` is a thin wrapper around it. The full option list, processing
order and outputs are documented in [intan2matlab.md](intan2matlab.md).

**`out = toMat(Name=Value)`** runs `deriveSignals` and saves `Y`, `events`,
`info` and a `conversion` provenance struct to one MAT-file.

| Option | Default |
| --- | --- |
| `File` | `<outputFolder>/<Name>_extract.mat` |
| `SignalOptions` | `struct()`: `deriveSignals` options |
| `MatVersion` | `"-v7.3"` (or `"-v7"`) |
| `Overwrite` | `false`: error `IntanDataset:toMat:Exists` if the file exists |
| `ProgressFcn` | none: `ProgressFcn(nDone, nTotal, message)`, with the save counted as one extra step |

The data is saved to `~<name>.partial.mat` first. The file is renamed to the
target only after `save()` finishes **without any warning** and every variable is
confirmed present with `whos -file`. Otherwise the partial file is deleted and an
error is raised, so a failed or cancelled run leaves no complete-looking file.
`out` fields: `file`, `bytes`, `seconds`, `matVersion`, `recordingFormat`,
`origFs`, `signals` (name, nSamples, nChannels, class, Fs), `events` (name,
count), `badChannels`.

### Dataset manifest

The manifest is a JSON state file at `<Folder>/<Name>_manifest.json`, i.e. in the
**recording folder**, not `OutputDir`. Its schema is in
[file-formats.md](file-formats.md#dataset-manifest).

- `manifestFile()` returns the path.
- `manifestStruct()` builds the snapshot: metadata, probe, exclusions, `.bin`
  state, latest Kilosort4 run from `tracker()`, and the SpikeInterface config.
- `writeManifest()` writes it. Failures only warn
  (`IntanDataset:writeManifest:Failed`).
- `applyManifest()` restores **only** `ProbeFile` (if the file still exists) and
  `ExcludeChannels`. Header metadata is always re-parsed; `ManualArtifacts`,
  `ArtifactConfig` and `SIConfig` are not stored or restored.

### Other helpers

| Method | Returns |
| --- | --- |
| `outputFolder()` | `OutputDir`, or `Folder` when `OutputDir` is `""` |
| `tracker()` | a [`DatasetTracker`](DatasetTracker.md) of `outputFolder()` (an empty tracker if the folder does not exist yet) |
| `IntanDataset.detectFormat(folder)` | layout string (static) |
| `IntanDataset.parseChannelList(s)` | sorted, unique, positive integer row vector from `"1,3,5-8"`, `"1 3 5:8"` or a numeric vector. Hyphens become colons and the text goes through `str2num` |
| `IntanDataset.formatChannelList(ch)` | compact `"1,3,5-8"` string |

---

## Main error identifiers

| Identifier | Raised when |
| --- | --- |
| `IntanDataset:NoFolder` | constructor folder missing |
| `IntanDataset:refreshMetadata:ChannelMismatch`, `IntanDataset:toBin:ChannelMismatch` | amplifier channel count changes between files |
| `IntanDataset:splitLayout:NoHeader` / `NoAmplifier` / `NoChannels` | split recording incomplete |
| `IntanDataset:readData:NoFiles`, `IntanDataset:toBin:NoFiles` | no Intan files |
| `IntanDataset:readData:BadKeepChannels`, `IntanDataset:toBin:BadChannelOrder` | channel index out of range |
| `IntanDataset:filterContinuous:CutoffAboveNyquist` | cutoff ≥ Fs/2 |
| `IntanDataset:runKilosort:NoPython` / `NoProbe` / `ProbeMissing` / `BinMissing` | run prerequisites missing |
| `IntanDataset:runSpikeInterface:NoPython` / `NoProbe` / `ProbeMissing` | run prerequisites missing |
| `IntanDataset:toMat:Exists` / `SaveWarning` / `SaveIncomplete` | `.mat` output refused or discarded |

## Tests

[`test_IntanDataset.m`](../intan/test_IntanDataset.m) builds synthetic `*.rhd`
and split-layout fixtures in a temp folder and deletes them afterwards. It covers:

| Section (as printed by the test) | Covers |
| --- | --- |
| 1-2 | `refreshMetadata` + header-only parse |
| 3 | `readData` (concatenation + events) |
| 4 | `toBin` streaming vs `matrix2kilosort` byte identity |
| 5 | `.bin` → microvolts round-trip |
| 6 | `filterContinuous` + `detectArtifacts` |
| 7 | `IntanKilosortProject` discovery |
| 8 | `runKilosort(DryRun=true)` |
| 9 | `DatasetTracker` integration |
| 10 | split layouts (metadata, `readData`, byte-correct `toBin`) |
| 11 | `artifactIntervals` (manual merge + automatic streaming) |
| 12 | `runSpikeInterface(DryRun=true)` |

It needs no real Intan data and no Kilosort4 install. (These tests were not run
as part of writing this documentation.)
