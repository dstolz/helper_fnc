# intan2matlab / deriveSignals / toMat

These three entry points run the same processing. It reads an Intan recording
(any layout), concatenates it in time, extracts digital-input events, and
derives LFP, MUA and/or spike-band signals.

| Entry point | What it is |
| --- | --- |
| [`intan2matlab(folder, ...)`](../intan/intan2matlab.m) | standalone function, a thin wrapper: `IntanDataset(folder)` then `deriveSignals(...)`. With no `ProgressFcn`, it prints a `parfor_progress` bar and a summary of auto-flagged bad channels |
| [`ds.deriveSignals(...)`](../intan/@IntanDataset/deriveSignals.m) | the implementation (an `IntanDataset` method) |
| [`ds.toMat(...)`](../intan/@IntanDataset/toMat.m) | `deriveSignals` + an atomic save to one `.mat` (see [IntanDataset](IntanDataset.md#derived-signals-the-intan2matlab-processing)) |
| GUI **Convert** tab | `toMat` over the selected datasets (see [IntanKilosortApp](IntanKilosortApp.md#convert)) |

> These files were edited (LFP band-limit and notch options added) while this
> documentation was being written. This page reflects the code as of that
> session; check the source help if in doubt.

```matlab
[Y, events, info] = intan2matlab("D:\rec\subj1_day1");
[Y, events, info] = intan2matlab("D:\rec\subj1_day1", dataTypeOut=["LFP" "MUA"], ...
    LFP_bpLoHi=[1 300], LFP_NotchHz=[60 120 180]);

ds = IntanDataset("D:\rec\subj1_day1");
out = ds.toMat(SignalOptions=struct('dataTypeOut', ["LFP" "SPIKE"]));
```

## Processing order

1. **Read** the whole recording with `readData(Precision="single")`:
   traditional files in chronological order, or the split `.dat` files. Only
   `keepAmpChannels` are kept, in the given order. Digital events are extracted
   here, at the original rate.
2. **LFP**, if requested: `resample` to `LFP_Fs`. If `LFP_bpLoHi` is not
   `[0 Inf]`, or `LFP_NotchHz` is non-empty, filters are then applied **at
   `LFP_Fs`**, one channel at a time in double precision:
   - a 4th-order Butterworth high-pass, low-pass or bandpass;
   - a 2nd-order Butterworth band-stop for each notch frequency;
   - each as second-order sections, applied with `filtfilt`.
3. **MUA**, if requested: 4th-order Butterworth bandpass `MUA_bpLoHi` at the
   original rate (`filtfilt`) → `abs` → `resample` to `MUA_Fs` → `movmean` with
   a window of `round(MUA_Fs / MUA_IntegrationHz)` samples.
4. **SPIKE**, if requested: `resample` to `SPIKE_Fs` (skipped when `Inf` or
   equal to the original rate) → 4th-order Butterworth bandpass `SPIKE_bpLoHi`
   designed at `SPIKE_Fs` (`filtfilt`).
5. **Bad channels**, if given: the listed columns are set to `NaN` in every
   derived signal and filled with `fillmissing(..., 'makima', 2)`.
   - This is interpolation across **neighboring columns in the kept order**. It
     does not use probe geometry.
   - A negative scalar `badChannels = -z` auto-flags channels with
     `abs(zscore(rms(Y.LFP))) > z`, computed on the LFP after any LFP filtering.
     This requires `"LFP"` and uses `zscore`, from the Statistics and Machine
     Learning Toolbox.
6. **Remap**, if given: `channelRemap` reorders the columns of every signal, and
   `info.labels` is reordered to match.

## Options

| Option | Default | Notes |
| --- | --- | --- |
| `dataTypeOut` | `"LFP"` | any of `"LFP"`, `"MUA"`, `"SPIKE"` |
| `keepAmpChannels` | `[]` (all) | 1-based amplifier channels, read in this order |
| `channelRemap` | `[]` | final column order, 1-based into the kept channels |
| `badChannels` | `[]` | column indices (after keep, before remap), or a negative scalar for auto |
| `LFP_Fs` | 1000 Hz | |
| `LFP_bpLoHi` | `[0 Inf]` | `0` = no high-pass, `Inf` = no low-pass. Finite edges must be < `LFP_Fs/2` |
| `LFP_NotchHz` | `[]` | notch centers, e.g. `[60 120 180]`. Each needs `f − BW/2 > 0` and `f + BW/2 < LFP_Fs/2` |
| `LFP_NotchBW` | 2 Hz | notch width. `f ± BW/2` are the −3 dB points of the design (−6 dB after `filtfilt`) |
| `MUA_Fs` | 2000 Hz | |
| `MUA_IntegrationHz` | 1000 Hz | |
| `MUA_bpLoHi` | `[300 5000]` | high edge < original Fs/2 |
| `SPIKE_Fs` | `Inf` (original rate) | |
| `SPIKE_bpLoHi` | `[300 5000]` | high edge < `SPIKE_Fs/2` |
| `labelField` | `"custom_channel_name"` | or `"native_channel_name"`; labels `info.labels` and names the `events` fields |
| `ProgressFcn` | `[]` | `ProgressFcn(nDone, nTotal, message)`: one step per file read, one per processing stage, then `(nTotal, nTotal, "Done")`. It may throw to abort. Not stored in `info` |

All options are validated before any data is read. Band edges are checked
against the header sample rate, and checked again against the rate actually read
if the two differ. Errors use `IntanDataset:deriveSignals:*` identifiers.
`intan2matlab` adds `INTAN2MATLAB:NoFiles`.

The help text notes that `filtfilt` IIR filtering leaves **edge transients** at
the start and end of the recording: up to about 2 s at each end for a 1 Hz
LFP high-pass, and longer for lower cut-offs.

## Outputs

**`Y`**: a struct with `LFP`, `MUA`, `SPIKE`, each `[nSamples x nChan]`.
Signals that were not requested are `single([])`.

**`events`**: one field per digital-input line. The field name is the line's
`labelField` name passed through `matlab.lang.makeValidName`. Each field is a
`[k x 2]` array of `[t_on t_off]` in seconds on the original amplifier time
base. Onset/offset times are (1-based sample index)/Fs; see
[Time conventions](README.md#time-and-indexing-conventions).

**`info`**:

| Field | Contents |
| --- | --- |
| `RHDroot` | recording folder |
| `filenames` | files read |
| `recordingFormat` | layout |
| `labels` | amplifier labels in `Y` column order |
| `origFs` | amplifier sample rate |
| `LFP` | `Fs`, `bpLoHi`, `NotchHz`, `NotchBW`, `filter` (text description of the filters applied), `time` |
| `MUA` | `Fs`, `IntegrationHz`, `bpLoHi`, `time` |
| `SPIKE` | `Fs`, `time` |
| `importOptions` | the options actually used: `SPIKE_Fs` replaced by `origFs` when `Inf`, and `badChannels` replaced by the channels actually interpolated |

The `LFP`/`MUA`/`SPIKE` sub-structs exist only for requested signals. Each
`time` vector is `(0:n−1)'/Fs`.

## Memory and requirements

- Amplifier data is read as `single`. The help text puts peak memory at about
  twice the single-precision recording.
- Requires the Signal Processing Toolbox (`butter`, `filtfilt`, `resample`,
  `zp2sos`). `bwlabel` (Image Processing Toolbox) is used for events when
  present, with an equivalent fallback otherwise. Auto bad-channel detection
  needs `zscore` (Statistics and Machine Learning Toolbox).
- `intan2matlab`'s console progress bar uses
  [`compute/parfor_progress.m`](../../compute/parfor_progress.m).
