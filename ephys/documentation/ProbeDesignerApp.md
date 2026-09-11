# ProbeDesignerApp

`ProbeDesignerApp` ([source](../intan/ProbeDesignerApp.m)) is a `handle` class
that opens a modal window for **building a Kilosort4 probe `.json`**. You can
start from a manufactured probe in the
[probeinterface library](https://github.com/SpikeInterface/probeinterface_library)
or from a generated standard geometry. You then wire each contact to an Intan
amplifier channel and save the result into the app's probe folder.

probeinterface is used only as the "front door". The designer calls
[`probe_tool.py`](python-drivers.md#probe_toolpy) in the sorting Python
environment, and writes a **plain Kilosort4 probe `.json`** (schema in
[file-formats.md](file-formats.md#kilosort4-probe-json)). Everything downstream
consumes only that JSON.

## Opening it

The designer is normally opened from the GUI: **Probe tab → "Design probe from
probeinterface (library / generate)..."**
([`IntanKilosortApp.onDesignProbe`](../intan/@IntanKilosortApp/onDesignProbe.m)).
Programmatically:

```matlab
app = IntanKilosortApp;
ProbeDesignerApp(app)          % or ProbeDesignerApp(app, nChanHint)
```

| Argument | Meaning |
| --- | --- |
| `app` | the parent `IntanKilosortApp`. The designer uses its `runProbeTool` (Python/conda from the Kilosort tab), `ProbeFolderField` / `defaultProbeFolder()` (save location) and `refreshProbeList()` (called after saving) |
| `nChanHint` | optional. The selected dataset's channel count. It is used only to append a note to the status line when the contact count differs; it does not block anything |

## Workflow

1. **Source**: pick *From probeinterface library* or *Generate geometry*.
2. **Library**:
   - **Load list** runs `probe_tool.py list-library`. The first run may need
     internet access; probeinterface caches afterwards.
   - Pick a manufacturer and a probe. The probe box is editable, so you can type
     a name that is not in the list.
   - **Fetch** runs `get-library` into a temp `.json` and loads it.
3. **Generate**: pick a type, set its parameters, then press **Build**. This runs
   `generate` with a temp spec `.json`.

   | Type | Parameters (defaults) |
   | --- | --- |
   | Linear | `num_elec` 16, `ypitch` 20 µm |
   | Multi-column | columns 2, per column 8, `xpitch` 22 µm, `ypitch` 20 µm |
   | Tetrode | radius `r` 10 µm |

4. **Wiring**: the table lists each contact with its x, y, shank and *Device
   ch*. Device ch is the **1-based** Intan amplifier channel the contact is wired
   to.
   - It is initialized from the fetched/built probe's `chanMap + 1`.
   - Edit a cell (must be a positive integer), or use a preset: **Identity**
     (1..n), **Reverse** (n..1) or **Load map...**.
   - **Load map...** accepts a `.csv`/`.txt` of one value per contact, a `.json`
     numeric array, or a `.json` with `chanMap`, which is read as 0-based and
     converted to 1-based. The number of entries must equal the contact count.
   - **Label ch** writes the device channel next to each contact in the preview.
5. **Name / Notes**: the name becomes the file name. Characters other than
   letters, digits, `_`, `-`, `.` are replaced with `_`, and a trailing `.json`
   is removed. It defaults to the probe name (library) or `linearN` / `mcCxN` /
   `tetrode` (generated). Notes are stored in the JSON `notes` field.
6. **Save to probe folder** writes `<probe folder>/<name>.json`. The probe
   folder is the Probe tab's folder, or `ephys/intan/probes` if that is blank or
   missing.

## What is written

On save, the wiring is converted back to 0-based and written as:

```json
{
  "notes":   "...",
  "chanMap": [0-based device channel per contact],
  "xc":      [...],
  "yc":      [...],
  "kcoords": [...],
  "n_chan":  max(source n_chan, number of contacts, max(chanMap)+1)
}
```

Before writing, the designer checks:

- An existing file prompts for **Overwrite**.
- Non-finite, non-positive or non-integer wiring blocks the save.
- **Duplicate** device channels (two contacts on one channel) prompt
  *Save anyway* / *Cancel*.

After saving, `app.refreshProbeList()` is called and the designer closes.
**Cancel** closes without writing. Library and generate temp files are written
to `tempname` locations and are not deleted by the designer.

## Requirements

- A Python executable set on the GUI's Kilosort tab, pointing at an environment
  with `probeinterface` (the `kilosort` env from
  [INSTALL.md](../intan/INSTALL.md) has it).
- Internet access for the first library download.
