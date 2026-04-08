# Slicer Scripts Overview

This folder currently contains four runnable Python scripts for use inside the 3D Slicer Python console.

## Common Usage Pattern

Run any script from the Slicer Python console with:

```python
exec(open(r"c:\src\helper_fnc\slicer\SCRIPT_NAME.py", encoding="utf-8").read())
```

## slicer_create_cannula.py

Opens a dialog for building a three-part cannula assembly anchored to a selected markup or control point. It creates a guide cannula, infusion cannula, and adapter as model nodes, then parents them to a shared transform so the whole assembly can be repositioned or rotated together in Slicer.

What you can set in the dialog:

- Target markup or control point
- Guide and infusion cannula diameters and lengths
- Guide cannula Z offset
- Adapter diameter and height
- Model opacity and ambient lighting
- Initial X/Y/Z rotation

Run in Slicer:

```python
exec(open(r"c:\src\helper_fnc\slicer\slicer_create_cannula.py", encoding="utf-8").read())
```

## slicer_calculate_node_translation.py

Used to calculate stereotaxic translations along the 3 axes typically from lambda to the brain surface (entry point).

Opens a dialog that lets you pick a start and finish markup location, then computes the required translation in RAS coordinates. It can also create a linear transform node and optional axis-aligned helper lines showing the X, Y, and Z components of the translation.

Requirements before running:

- At least two markup nodes or control points must exist in the scene.

Run in Slicer:

```python
exec(open(r"c:\src\helper_fnc\slicer\slicer_calculate_node_translation.py", encoding="utf-8").read())
```

## slicer_measure_point_distance_angle.py

Typically used to calculate the distance and angle(s) from the surface of the brain (entry point) to the target location (infusion site)

Opens a dialog for selecting two markups or individual control points, then measures the 3D distance between them in RAS space. It also reports the signed angle from vertical (Z/IS) in the Y/AP and X/LR planes, along with the overall angle from vertical.

Requirements before running:

- At least two markup nodes or control points must exist in the scene.

Optional behavior in the dialog:

- Draw a markup line between the selected points
- Override the generated line node name

Outputs:

- Point 1 and Point 2 world positions in RAS coordinates
- Point-to-point delta in RAS coordinates
- 3D distance in mm
- Signed angle from vertical in the Y/AP plane
- Signed angle from vertical in the X/LR plane
- Overall angle from vertical
- An optional line markup node connecting the two selected points

Run in Slicer:

```python
exec(open(r"c:\src\helper_fnc\slicer\slicer_measure_point_distance_angle.py", encoding="utf-8").read())
```



## slicer_batch_axial_slice_screencapture.py

Creates a sequence of PNG screenshots while stepping the Red slice view through a Z range. The script switches Slicer to the Four-Up layout, forces a render for each position, captures the main window, optionally scales the image, and writes files to `output_dir`.

Edit these parameters near the top of the file before running:

- `output_dir`: destination folder for PNG files
- `start_z`, `end_z`, `step`: slice offsets in mm
- `scale_factor`: output image scaling factor

Run in Slicer:

```python
exec(open(r"c:\src\helper_fnc\slicer\slicer_batch_axial_slice_screencapture.py", encoding="utf-8").read())
```


## Notes

- These scripts are intended to be executed inside 3D Slicer, not from a standard system Python interpreter.
- The `CannulaTool` subfolder is currently empty in this workspace.