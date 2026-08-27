# Installing `IntanKilosortApp` on Windows 11

`IntanKilosortApp` is a MATLAB App Designer-style GUI (`ephys/intan/@IntanKilosortApp`)
that scans Intan `.rhd` recordings, previews/filters them, and hands them off to
**SpikeInterface + Kilosort4** (running in a separate Python/conda environment) for
spike sorting, with **phy** as the optional curation viewer at the end. This guide
covers everything needed to get a clean Windows 11 machine running the app end to end.

## What you need, at a glance

| Component | Purpose | Required? |
| --- | --- | --- |
| MATLAB + Signal Processing Toolbox | Runs the app, reads/filters Intan data | Yes |
| Miniconda (Windows) | Hosts the Python environments below | Yes |
| `kilosort` conda env (spikeinterface, kilosort, probeinterface, neo, torch) | Runs the sorting pipeline | Yes |
| NVIDIA GPU + driver | Kilosort4 runs dramatically faster on GPU | Recommended, not required |
| `phy2` conda env (phy) | Manual curation of sorting results | Optional |
| This repository (`helper_fnc`) | Contains the app and MATLAB path helpers | Yes |

## 1. Install MATLAB

1. Install MATLAB R2021a or later (the app uses App Designer grid layouts,
   `arguments`-block validation, and string arrays that need a reasonably
   recent release).
2. In the Add-On Explorer / installer, make sure **Signal Processing Toolbox**
   is included — `IntanDataset.filterContinuous` calls `butter`/`filtfilt`
   directly and the Visualize tab's filtering options depend on it.

## 2. Get the repository onto your MATLAB path

1. Install [Git for Windows](https://git-scm.com/download/win) if you don't
   already have it, then clone this repo (or download/unzip it) to somewhere
   like `C:\src\helper_fnc`.
2. In MATLAB, `cd` to the repo root and run:
   ```matlab
   addpath_nogit(pwd)
   ```
   This adds the repo (including `ephys/intan`) to the path while skipping
   `.git` folders. Save the path (`savepath`) if you want this to persist
   across MATLAB restarts, or re-run it each session.

## 3. (Recommended) Set up an NVIDIA GPU

Kilosort4 can run on CPU, but it is very slow for anything beyond a quick
test. If the machine has an NVIDIA GPU:

1. Install the latest **NVIDIA driver** for the card from
   [nvidia.com/drivers](https://www.nvidia.com/Download/index.aspx) (Game
   Ready or Studio driver, either works). You do **not** need to separately
   install the CUDA Toolkit — the PyTorch wheel installed in step 4 bundles
   its own CUDA runtime.
2. No further action needed until step 4, where you'll install a
   CUDA-enabled build of PyTorch.

If there's no NVIDIA GPU, skip to step 4 and install the CPU build of
PyTorch instead — everything still works, just slower.

## 4. Install Miniconda and the `kilosort` environment

1. Install [Miniconda for Windows](https://docs.conda.io/en/latest/miniconda.html)
   (the 64-bit installer). Default install location is fine
   (`%USERPROFILE%\miniconda3` or `%LOCALAPPDATA%\miniconda3` — the app's
   "Browse Python exe" picker and `IntanKilosortApp.defaultPythonExe()` both
   look for these paths automatically).
2. Open **Anaconda Prompt (miniconda3)** from the Start menu and create the
   environment the app expects, named `kilosort`:
   ```bat
   conda create -n kilosort python=3.10 -y
   conda activate kilosort
   ```
3. Install the sorting stack:
   ```bat
   pip install spikeinterface[full]==0.104.5 kilosort==4.1.7 probeinterface==0.3.2 neo==0.14.4
   ```
4. Install PyTorch:
   - **With an NVIDIA GPU (CUDA 11.8):**
     ```bat
     pip install torch==2.7.1 --index-url https://download.pytorch.org/whl/cu118
     ```
   - **CPU only:**
     ```bat
     pip install torch==2.7.1
     ```
5. Sanity check the environment:
   ```bat
   python -c "import spikeinterface, kilosort, probeinterface, torch; print(torch.cuda.is_available())"
   ```
   This should print `True` if the GPU build installed correctly, or `False`
   (no error) for a CPU-only setup.

You do **not** need conda on the Windows `PATH` for the app to work — it
calls the environment's `python.exe` directly by full path
(`%USERPROFILE%\miniconda3\envs\kilosort\python.exe` or similar).

## 5. (Optional) Install `phy` for manual curation

`phy` has its own, older dependency set that conflicts with the `kilosort`
env, so it needs its own environment. From Anaconda Prompt:

```bat
conda create -n phy2 python=3.11 -y
conda activate phy2
pip install phy --pre --upgrade
```

Skip this if you don't plan to manually curate sorting results — Kilosort4
still runs and writes phy-format output either way.

## 6. Point the app at your Python environments

1. Launch the app in MATLAB:
   ```matlab
   IntanKilosortApp
   ```
2. Go to the **Kilosort** tab:
   - **Python exe** — should auto-fill with
     `...\miniconda3\envs\kilosort\python.exe` if it's in a standard location;
     otherwise browse to it with the `...` button.
   - **Conda env** — leave blank (the Python exe above already points inside
     the `kilosort` env).
   - **Phy command** — leave as `phy` if you installed it into the base/PATH
     environment, or set it to `conda run -n phy2 phy` if you used the
     separate `phy2` env from step 5.

## 7. Verify everything works

Before running a full dataset, use the pipeline's built-in dry run: on the
Kilosort tab, saving your configuration and running the generated
`run_si_ks4.py` with `--check` will read a recording, attach the probe, and
build the preprocessing chain **without** running Kilosort4 — the fastest way
to confirm the environment and a given recording format are compatible. See
`IntanDataset.runSpikeInterface` for how this is invoked from MATLAB.

## Troubleshooting

- **"No python executable configured"** — set the Python exe field on the
  Kilosort tab (or `ds.PythonExe` if scripting `IntanDataset` directly).
- **`neo`/`read_intan` errors about a missing `.dat` file** — split-format
  Intan recordings need every declared stream's `.dat` file present (e.g.
  `digitalin.dat`), even if you don't use that stream.
- **`torch.cuda.is_available()` returns `False` on a GPU machine** — the
  wrong PyTorch build was installed (CPU wheel instead of `+cu118`); reinstall
  using the CUDA index URL in step 4, and confirm the NVIDIA driver installed
  in step 3 is current.
- **phy fails to launch** — confirm `params.py` exists in the dataset's
  Kilosort4 results folder, and that the "Phy command" field matches how you
  installed phy (base env vs. `conda run -n phy2 phy`).
