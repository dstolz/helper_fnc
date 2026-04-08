# helper_fnc

Utility repository of MATLAB helpers plus task-specific automation for histology workflows, image processing, plotting, 3D Slicer, Fiji, and Photoshop.

Most of the repository is MATLAB code intended to be added to the MATLAB path and called from analysis scripts. The non-MATLAB folders contain host-application scripts that are meant to run inside Fiji/ImageJ, Adobe Photoshop, or 3D Slicer.

## Table of Contents

- [Quick Start](#quick-start)
- [Repository Map](#repository-map)
- [MATLAB Utilities](#matlab-utilities)
- [Histology Tools](#histology-tools)
- [3D Slicer Scripts](#3d-slicer-scripts)
- [Fiji / ImageJ Macros](#fiji--imagej-macros)
- [Photoshop Automation](#photoshop-automation)
- [Dependencies and Environment Notes](#dependencies-and-environment-notes)
- [Suggested Entry Points](#suggested-entry-points)

## Quick Start

### MATLAB

Add the repository and its subfolders to the MATLAB path while skipping `.git` folders:

```matlab
addpath_nogit(pwd)
```

If you keep multiple tagged copies of a project under a common parent folder, `tools/use_version.m` can swap the active MATLAB path to a selected release.

### 3D Slicer

Run Slicer scripts from the Slicer Python console:

```python
exec(open(r"c:\src\helper_fnc\slicer\SCRIPT_NAME.py", encoding="utf-8").read())
```

### Fiji / ImageJ

Open the `.ijm` macro in Fiji and run it from the Script Editor or Macro runner.

### Photoshop

Run the `.jsx` automation scripts from Photoshop's Scripts workflow.

## Repository Map

| Path | Purpose |
| --- | --- |
| `addpath_nogit.m` | Add this repository to the MATLAB path without pulling in `.git` folders. |
| `compute/` | Numerical helpers for AUROC, event-aligned spike summaries, DTW, hashing, and `parfor` progress tracking. |
| `file_handling/` | Small file and remote-data import utilities. |
| `function_helpers/` | Tiny general-purpose MATLAB helper functions. |
| `gui/` | Figure helpers, plot labeling helpers, raster plotting, and colormaps. |
| `histology/` | Histology image processing, interactive alignment tools, cortex straightening, and labeling GUIs. |
| `plotting/` | Plotting utilities that do not fit the generic GUI folder. |
| `slicer/` | 3D Slicer Python scripts for cannula creation, coordinate measurements, and slice capture. |
| `fiji_scripts/` | Fiji/ImageJ macros for projection, ROI, segmentation, and image export workflows. |
| `photoshop_scripts/` | Photoshop batch photomerge automation scripts. |
| `tools/` | Workflow support classes and path/version utilities. |
| `validators/` | MATLAB argument-validation helpers. |

## MATLAB Utilities

### Root

| File | Summary |
| --- | --- |
| `addpath_nogit.m` | Adds a folder tree to the MATLAB search path while excluding `.git` directories. |

### `compute/`

| File | Summary |
| --- | --- |
| `auROC_response_curve.m` | Builds an AUROC response curve from event-aligned histogram data. |
| `compute_auroc.m` | Computes time-resolved AUROC values against a baseline window from firing-rate data. |
| `DBA.m` | Dynamic Time Warping Barycenter Averaging implementation with internal helper routines. |
| `DBA_dtw.m` | DTW distance helper used with DBA-style sequence averaging workflows. |
| `dtwf.m` | Fast dynamic time warping distance function for one-dimensional signals. |
| `dtwf3.m` | Variant of DTW distance computation, likely for alternate signal shapes or optimization paths. |
| `event_hist.m` | Event-aligned spike histogram utility. |
| `event_hist_sliding.m` | Event-aligned histogram with overlapping sliding windows. |
| `event_spike_count.m` | Counts spikes in a specified window around each event. |
| `md5.m` | Returns the MD5 hash of a file. |
| `parfor_progress.m` | Tracks progress during `parfor` execution. |

### `file_handling/`

| File | Summary |
| --- | --- |
| `GetGoogleSpreadsheet.m` | Downloads and parses a public Google Spreadsheet as MATLAB data. |

### `function_helpers/`

| File | Summary |
| --- | --- |
| `errEmpty.m` | Small helper that returns `[]`, useful in error-handling branches such as `cellfun` wrappers. |
| `structToCallerVars.m` | Assigns structure fields into the caller workspace. |
| `ternary.m` | Minimal ternary-style conditional helper. |

### `gui/`

| File | Summary |
| --- | --- |
| `colorcet.m` | ColorCET colormap library bundled for MATLAB use. |
| `inferno.m` | Inferno colormap. |
| `magma.m` | Magma colormap. |
| `plasma.m` | Plasma colormap. |
| `viridis.m` | Viridis colormap. |
| `plot_raster.m` | Draws a simple spike raster from a cell array of spike-time vectors. |
| `subtitlef.m` | Figure subtitle helper. |
| `titlef.m` | Figure title helper. |
| `use_fig.m` | Reuses or creates a named figure and clears it for fresh plotting. |
| `use_fig_tiledlayout.m` | Convenience wrapper for creating/reusing a figure with a tiled layout. |
| `xlabelf.m` | X-label helper. |
| `ylabelf.m` | Y-label helper. |
| `xyline.m` | Adds an `x=y` style reference line to an axes. |

### `plotting/`

| File | Summary |
| --- | --- |
| `secondaryAxis.m` | Overlays a synchronized secondary x- or y-axis using a custom mapping function. |

### `tools/`

| File | Summary |
| --- | --- |
| `Manifest.m` | Handle class for recording analysis/preprocessing steps with timestamps, notes, and parameters. |
| `use_version.m` | Switches the MATLAB path to a selected versioned release folder. |
| `@DataPrefs/DataPrefs.m` | XML-backed class for storing file lists and per-file metadata such as inclusion flags. |
| `@DataPrefs/showGUI.m` | GUI for reviewing and editing `DataPrefs` entries. |

### `validators/`

| File | Summary |
| --- | --- |
| `mustBeAscending.m` | Custom validator that enforces ascending two-element input ranges. |

## Histology Tools

The `histology/` folder is the most specialized part of the repository. It contains both reusable image-processing functions and interactive tools for image registration, thresholding, and crop review.

| File | Summary |
| --- | --- |
| `extract_equal_area_profiles.m` | Samples image intensity across trapezoidal regions laid out along a curve and returns profile metrics. |
| `histologyLabeller.m` | Interactive montage browser for labeling image crops or paired image sets. |
| `InteractiveAffineOverlay.m` | Keyboard-driven affine overlay tool for aligning a foreground image onto a background image. |
| `InteractiveRotator.m` | Interactive image rotation helper used by other histology workflows. |
| `organize_images_by_section_gui.m` | GUI for reorganizing images by tissue section. |
| `parabola_offset.m` | Computes offset curves and arc lengths for parabolic profile construction. |
| `parseBfTiff.m` | Reads OME-TIFF data through Bio-Formats and returns image channels plus metadata. |
| `straightenLine.m` | Straightens image content sampled along a user-defined line. |
| `straighten_cortex.m` | End-to-end cortex straightening and profile extraction pipeline for histology OME-TIFF images. |
| `straighten_cortex2.m` | Alternative cortex-straightening implementation. |
| `ThresholdAdjuster.m` | Interactive threshold tuning tool with boundary overlays. |
| `T_HistologyBrainSurface.m` | Test or exploratory script related to histology brain-surface workflows. |
| `T_Overlay.m` | Test or exploratory script for image overlay workflows. |
| `T_ShowSections.m` | Test or exploratory script for viewing section data. |

## 3D Slicer Scripts

The `slicer/` folder contains Python scripts designed to run inside the 3D Slicer Python console.

| File | Summary |
| --- | --- |
| `slicer_create_cannula.py` | Opens a dialog to build a three-part cannula assembly anchored to a selected markup or control point. |
| `slicer_calculate_node_translation.py` | Calculates RAS-space translations between selected markup points and can create helper transforms/lines. |
| `slicer_measure_point_distance_angle.py` | Measures point-to-point distance and signed angles from vertical between two selected Slicer points. |
| `slicer_batch_axial_slice_screencapture.py` | Captures a series of axial slice screenshots across a user-defined Z range. |
| `CannulaTool/` | Placeholder subfolder in this workspace; no runnable content is currently documented there. |
| `README.md` | Folder-specific usage notes and script details for the Slicer tools. |

## Fiji / ImageJ Macros

These scripts are intended for Fiji/ImageJ macro execution.

| File | Summary |
| --- | --- |
| `Library.txt` | Support/reference file associated with the Fiji macro workflow. |
| `MACRO_Batch_genComposites.ijm` | Recursively imports `.czi` images via Bio-Formats, performs projections, and writes processed composite outputs. |
| `MACRO_Batch_generateSegmentationMaps.ijm` | Batch segmentation pipeline using Labkit, with optional ROI masking and skip-if-output-exists behavior. |
| `MACRO_Batch_ROI.ijm` | ROI-oriented batch macro for Fiji workflows. |
| `MACRO_Batch_TIF2PNG.ijm` | Batch conversion utility for exporting TIFF images as PNG. |

## Photoshop Automation

These scripts run inside Photoshop and automate multi-image stitching workflows.

| File | Summary |
| --- | --- |
| `AutomatePhotomerge.jsx` | Batch photomerge pipeline that recursively stitches folders of images using translation-only alignment with logging and safety guards. |
| `AutomatePhotomerge_InteractiveAlignment.jsx` | Batch photomerge variant that prompts once for the alignment mode before processing. |

## Dependencies and Environment Notes

- MATLAB is the primary environment for the `.m` utilities.
- Several histology functions depend on Bio-Formats and Image Processing Toolbox-style functionality.
- Fiji macros expect Fiji/ImageJ plugins such as Bio-Formats and, for segmentation, Labkit.
- Slicer scripts must be executed inside 3D Slicer rather than a standard Python interpreter.
- Photoshop scripts target Adobe Photoshop's ExtendScript environment.

## Suggested Entry Points

If you are new to the repository, these are the fastest places to start:

1. Run `addpath_nogit(pwd)` in MATLAB.
2. Browse `compute/`, `gui/`, and `tools/` for general reusable helpers.
3. Use `histology/` for image-analysis workflows tied to cortical surface extraction and alignment.
4. Use `slicer/`, `fiji_scripts/`, and `photoshop_scripts/` only from their host applications.
