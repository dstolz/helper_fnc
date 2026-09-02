import math
import slicer
import vtk
import qt


# exec(open(r"c:\src\helper_fnc\slicer\slicer_create_cannula.py", encoding="utf-8").read())

# Default parameters shown in the dialog
DEFAULT_MARKUP_NAME = "LAC"
DEFAULT_GUIDE_CANNULA_DIAMETER_INCH = 0.018
DEFAULT_GUIDE_CANNULA_LENGTH_MM = 6.0
DEFAULT_GUIDE_CANNULA_Z_OFFSET_MM = 1.0

DEFAULT_INFUSION_CANNULA_DIAMETER_INCH = 0.008
DEFAULT_INFUSION_CANNULA_LENGTH_MM = 7.0

DEFAULT_ADAPTER_DIAMETER_MM = 3.0
DEFAULT_ADAPTER_HEIGHT_MM = 4.0

DEFAULT_OPACITY = 0.65
DEFAULT_AMBIENT = 1.00
DEFAULT_ROTATION_X_DEG = 0.0
DEFAULT_ROTATION_Y_DEG = 0.0
DEFAULT_ROTATION_Z_DEG = 0.0

# Approximate RGB colors
SILVER = (0.75, 0.75, 0.75)
BRASS = (0.71, 0.65, 0.26)


def get_point_from_markup_name(markup_name):
    """
    Resolve markup_name as either:
      - an internal selector value from the dialog dropdown,
      - a control-point label in any markups node, or
      - a markups node name (control point 0 is used).
    Returns: (markupsNode, controlPointIndex, worldPoint)
    """
    if markup_name.startswith("control_point::"):
        _, node_id, control_point_index = markup_name.split("::", 2)
        node = slicer.mrmlScene.GetNodeByID(node_id)
        if not node or not node.IsA("vtkMRMLMarkupsNode"):
            raise ValueError(f"Could not find markups node for selector '{markup_name}'.")
        control_point_index = int(control_point_index)
        if control_point_index < 0 or control_point_index >= node.GetNumberOfControlPoints():
            raise ValueError(f"Control point selector '{markup_name}' is out of range.")
        p = [0.0, 0.0, 0.0]
        node.GetNthControlPointPositionWorld(control_point_index, p)
        return node, control_point_index, p

    if markup_name.startswith("node::"):
        _, node_id = markup_name.split("::", 1)
        node = slicer.mrmlScene.GetNodeByID(node_id)
        if not node or not node.IsA("vtkMRMLMarkupsNode"):
            raise ValueError(f"Could not find markups node for selector '{markup_name}'.")
        if node.GetNumberOfControlPoints() < 1:
            raise ValueError(f"Markups node '{node.GetName()}' has no control points.")
        p = [0.0, 0.0, 0.0]
        node.GetNthControlPointPositionWorld(0, p)
        return node, 0, p

    matches = []

    for node in slicer.util.getNodesByClass("vtkMRMLMarkupsNode"):
        n = node.GetNumberOfControlPoints()
        for i in range(n):
            if node.GetNthControlPointLabel(i) == markup_name:
                p = [0.0, 0.0, 0.0]
                node.GetNthControlPointPositionWorld(i, p)
                matches.append((node, i, p))

    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        raise ValueError(
            f"More than one control point has label '{markup_name}'. Use a unique label or rename duplicates."
        )

    # Fallback: treat markup_name as a node name.
    try:
        node = slicer.util.getNode(markup_name)
    except Exception:
        node = None

    if node and node.IsA("vtkMRMLMarkupsNode"):
        if node.GetNumberOfControlPoints() < 1:
            raise ValueError(f"Markups node '{markup_name}' has no control points.")
        p = [0.0, 0.0, 0.0]
        node.GetNthControlPointPositionWorld(0, p)
        if node.GetNumberOfControlPoints() > 1:
            print(
                f"Node '{markup_name}' contains multiple control points; using control point 0 "
                f"('{node.GetNthControlPointLabel(0)}')."
            )
        return node, 0, p

    raise ValueError(
        f"Could not find a control-point label or markups node named '{markup_name}'."
    )


def remove_node_if_exists(node_name):
    nodes = slicer.util.getNodesByClass("vtkMRMLNode")
    to_remove = []
    for node in nodes:
        if node and node.GetName() == node_name:
            to_remove.append(node)
    for node in to_remove:
        slicer.mrmlScene.RemoveNode(node)


def get_available_markup_options():
    options = []

    for node in slicer.util.getNodesByClass("vtkMRMLMarkupsNode"):
        node_id = node.GetID()
        node_name = node.GetName() or node_id
        control_point_count = node.GetNumberOfControlPoints()

        if control_point_count > 0:
            options.append({
                "display_text": f"{node_name} [node]",
                "selector": f"node::{node_id}",
                "match_names": [node_name],
            })

        for control_point_index in range(control_point_count):
            label = node.GetNthControlPointLabel(control_point_index) or f"Point {control_point_index}"
            options.append({
                "display_text": f"{label} ({node_name})",
                "selector": f"control_point::{node_id}::{control_point_index}",
                "match_names": [label, f"{label} ({node_name})"],
            })

    return options



def add_cylinder_local(center_local, axis_vector, length_mm, radius_mm, name, color_rgb,
                       opacity=0.65, ambient=1.0, resolution=72):
    """
    Create a cylinder model in local coordinates.
    vtkCylinderSource is aligned with its local +Y axis.
    The cylinder is positioned relative to the local assembly origin; a parent
    transform node places and rotates the full assembly in world coordinates.
    """
    axis_len = math.sqrt(sum(v * v for v in axis_vector))
    if axis_len <= 0:
        raise ValueError("Axis vector must have non-zero length.")

    y_axis_local = [v / axis_len for v in axis_vector]

    if abs(y_axis_local[0]) < 0.9:
        reference = [1.0, 0.0, 0.0]
    else:
        reference = [0.0, 1.0, 0.0]

    z_axis_local = [
        y_axis_local[1] * reference[2] - y_axis_local[2] * reference[1],
        y_axis_local[2] * reference[0] - y_axis_local[0] * reference[2],
        y_axis_local[0] * reference[1] - y_axis_local[1] * reference[0],
    ]
    z_len = math.sqrt(sum(v * v for v in z_axis_local))
    z_axis_local = [v / z_len for v in z_axis_local]

    x_axis_local = [
        y_axis_local[1] * z_axis_local[2] - y_axis_local[2] * z_axis_local[1],
        y_axis_local[2] * z_axis_local[0] - y_axis_local[0] * z_axis_local[2],
        y_axis_local[0] * z_axis_local[1] - y_axis_local[1] * z_axis_local[0],
    ]

    cylinder = vtk.vtkCylinderSource()
    cylinder.SetRadius(radius_mm)
    cylinder.SetHeight(length_mm)
    cylinder.SetResolution(resolution)
    cylinder.CappingOn()

    matrix = vtk.vtkMatrix4x4()
    matrix.Identity()
    for row in range(3):
        matrix.SetElement(row, 0, x_axis_local[row])
        matrix.SetElement(row, 1, y_axis_local[row])
        matrix.SetElement(row, 2, z_axis_local[row])
        matrix.SetElement(row, 3, center_local[row])

    transform = vtk.vtkTransform()
    transform.SetMatrix(matrix)

    transform_filter = vtk.vtkTransformPolyDataFilter()
    transform_filter.SetTransform(transform)
    transform_filter.SetInputConnection(cylinder.GetOutputPort())
    transform_filter.Update()

    model_node = slicer.modules.models.logic().AddModel(transform_filter.GetOutputPort())
    model_node.SetName(name)

    display_node = model_node.GetDisplayNode()
    display_node.SetColor(color_rgb[0], color_rgb[1], color_rgb[2])
    display_node.SetOpacity(opacity)
    display_node.SetAmbient(ambient)
    display_node.SetVisibility(True)
    if hasattr(display_node, "SetLineWidth"):
        display_node.SetLineWidth(2)
    if hasattr(display_node, "SetVisibility2D"):
        display_node.SetVisibility2D(True)
    elif hasattr(display_node, "SetSliceIntersectionVisibility"):
        display_node.SetSliceIntersectionVisibility(True)

    return model_node



def create_rotation_transform(rotation_deg=None):
    transform = vtk.vtkTransform()
    transform.Identity()

    if rotation_deg is not None:
        transform.RotateX(rotation_deg[0])
        transform.RotateY(rotation_deg[1])
        transform.RotateZ(rotation_deg[2])

    return transform


def rotate_local_point(transform, point_local):
    rotated_point = [0.0, 0.0, 0.0]
    transform.TransformPoint(point_local, rotated_point)
    return rotated_point


def rotate_local_vector(transform, vector_local):
    rotated_vector = [0.0, 0.0, 0.0]
    transform.TransformVector(vector_local, rotated_vector)
    return rotated_vector


def create_linear_transform_node(name, translation_ras=None):
    transform_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLinearTransformNode", name)
    matrix = vtk.vtkMatrix4x4()
    matrix.Identity()

    if translation_ras is not None:
        matrix.SetElement(0, 3, translation_ras[0])
        matrix.SetElement(1, 3, translation_ras[1])
        matrix.SetElement(2, 3, translation_ras[2])

    transform_node.SetMatrixTransformToParent(matrix)
    return transform_node



def prompt_user_parameters():
    dialog = qt.QDialog(slicer.util.mainWindow())
    dialog.setWindowTitle("Create Cylinder Assembly")
    form_layout = qt.QFormLayout(dialog)

    markup_options = get_available_markup_options()
    markup_name_combo = qt.QComboBox()
    markup_name_combo.setEditable(True)
    markup_name_combo.setInsertPolicy(qt.QComboBox.NoInsert)

    for option in markup_options:
        markup_name_combo.addItem(option["display_text"], option["selector"])

    def set_markup_selection(markup_name):
        for index, option in enumerate(markup_options):
            if markup_name in option["match_names"]:
                markup_name_combo.setCurrentIndex(index)
                return
        markup_name_combo.setEditText(markup_name)

    set_markup_selection(DEFAULT_MARKUP_NAME)

    guide_cannula_diameter_inch_spin = qt.QDoubleSpinBox()
    guide_cannula_diameter_inch_spin.decimals = 4
    guide_cannula_diameter_inch_spin.minimum = 0.0001
    guide_cannula_diameter_inch_spin.maximum = 100.0
    guide_cannula_diameter_inch_spin.singleStep = 0.001
    guide_cannula_diameter_inch_spin.value = DEFAULT_GUIDE_CANNULA_DIAMETER_INCH

    guide_cannula_length_spin = qt.QDoubleSpinBox()
    guide_cannula_length_spin.decimals = 3
    guide_cannula_length_spin.minimum = 0.001
    guide_cannula_length_spin.maximum = 1000.0
    guide_cannula_length_spin.singleStep = 0.5
    guide_cannula_length_spin.value = DEFAULT_GUIDE_CANNULA_LENGTH_MM

    guide_cannula_offset_spin = qt.QDoubleSpinBox()
    guide_cannula_offset_spin.decimals = 3
    guide_cannula_offset_spin.minimum = -1000.0
    guide_cannula_offset_spin.maximum = 1000.0
    guide_cannula_offset_spin.singleStep = 0.5
    guide_cannula_offset_spin.value = DEFAULT_GUIDE_CANNULA_Z_OFFSET_MM

    infusion_cannula_diameter_inch_spin = qt.QDoubleSpinBox()
    infusion_cannula_diameter_inch_spin.decimals = 4
    infusion_cannula_diameter_inch_spin.minimum = 0.0001
    infusion_cannula_diameter_inch_spin.maximum = 100.0
    infusion_cannula_diameter_inch_spin.singleStep = 0.001
    infusion_cannula_diameter_inch_spin.value = DEFAULT_INFUSION_CANNULA_DIAMETER_INCH

    infusion_cannula_length_spin = qt.QDoubleSpinBox()
    infusion_cannula_length_spin.decimals = 3
    infusion_cannula_length_spin.minimum = 0.001
    infusion_cannula_length_spin.maximum = 1000.0
    infusion_cannula_length_spin.singleStep = 0.5
    infusion_cannula_length_spin.value = DEFAULT_INFUSION_CANNULA_LENGTH_MM

    adapter_diameter_spin = qt.QDoubleSpinBox()
    adapter_diameter_spin.decimals = 3
    adapter_diameter_spin.minimum = 0.001
    adapter_diameter_spin.maximum = 1000.0
    adapter_diameter_spin.singleStep = 0.5
    adapter_diameter_spin.value = DEFAULT_ADAPTER_DIAMETER_MM

    adapter_height_spin = qt.QDoubleSpinBox()
    adapter_height_spin.decimals = 3
    adapter_height_spin.minimum = 0.001
    adapter_height_spin.maximum = 1000.0
    adapter_height_spin.singleStep = 0.5
    adapter_height_spin.value = DEFAULT_ADAPTER_HEIGHT_MM

    opacity_spin = qt.QDoubleSpinBox()
    opacity_spin.decimals = 2
    opacity_spin.minimum = 0.0
    opacity_spin.maximum = 1.0
    opacity_spin.singleStep = 0.05
    opacity_spin.value = DEFAULT_OPACITY

    ambient_spin = qt.QDoubleSpinBox()
    ambient_spin.decimals = 2
    ambient_spin.minimum = 0.0
    ambient_spin.maximum = 1.0
    ambient_spin.singleStep = 0.05
    ambient_spin.value = DEFAULT_AMBIENT

    rotation_x_spin = qt.QDoubleSpinBox()
    rotation_x_spin.decimals = 3
    rotation_x_spin.minimum = -360.0
    rotation_x_spin.maximum = 360.0
    rotation_x_spin.singleStep = 1.0
    rotation_x_spin.value = DEFAULT_ROTATION_X_DEG

    rotation_y_spin = qt.QDoubleSpinBox()
    rotation_y_spin.decimals = 3
    rotation_y_spin.minimum = -360.0
    rotation_y_spin.maximum = 360.0
    rotation_y_spin.singleStep = 1.0
    rotation_y_spin.value = DEFAULT_ROTATION_Y_DEG

    rotation_z_spin = qt.QDoubleSpinBox()
    rotation_z_spin.decimals = 3
    rotation_z_spin.minimum = -360.0
    rotation_z_spin.maximum = 360.0
    rotation_z_spin.singleStep = 1.0
    rotation_z_spin.value = DEFAULT_ROTATION_Z_DEG

    form_layout.addRow("Markup / fiducial name:", markup_name_combo)
    form_layout.addRow("GuideCannula diameter (in):", guide_cannula_diameter_inch_spin)
    form_layout.addRow("GuideCannula length (mm):", guide_cannula_length_spin)
    form_layout.addRow("GuideCannula Z offset (mm):", guide_cannula_offset_spin)
    form_layout.addRow("InfusionCannula diameter (in):", infusion_cannula_diameter_inch_spin)
    form_layout.addRow("InfusionCannula length (mm):", infusion_cannula_length_spin)
    form_layout.addRow("Adapter diameter (mm):", adapter_diameter_spin)
    form_layout.addRow("Adapter height (mm):", adapter_height_spin)
    form_layout.addRow("Opacity:", opacity_spin)
    form_layout.addRow("Ambient:", ambient_spin)
    form_layout.addRow("Initial rotation X (LR, deg):", rotation_x_spin)
    form_layout.addRow("Initial rotation Y (AP, deg):", rotation_y_spin)
    form_layout.addRow("Initial rotation Z (IS, deg):", rotation_z_spin)

    button_box = qt.QDialogButtonBox()
    button_box.setStandardButtons(qt.QDialogButtonBox.Ok | qt.QDialogButtonBox.Cancel)
    reset_button = button_box.addButton("Reset Defaults", qt.QDialogButtonBox.ResetRole)

    def reset_defaults():
        set_markup_selection(DEFAULT_MARKUP_NAME)
        guide_cannula_diameter_inch_spin.value = DEFAULT_GUIDE_CANNULA_DIAMETER_INCH
        guide_cannula_length_spin.value = DEFAULT_GUIDE_CANNULA_LENGTH_MM
        guide_cannula_offset_spin.value = DEFAULT_GUIDE_CANNULA_Z_OFFSET_MM
        infusion_cannula_diameter_inch_spin.value = DEFAULT_INFUSION_CANNULA_DIAMETER_INCH
        infusion_cannula_length_spin.value = DEFAULT_INFUSION_CANNULA_LENGTH_MM
        adapter_diameter_spin.value = DEFAULT_ADAPTER_DIAMETER_MM
        adapter_height_spin.value = DEFAULT_ADAPTER_HEIGHT_MM
        opacity_spin.value = DEFAULT_OPACITY
        ambient_spin.value = DEFAULT_AMBIENT
        rotation_x_spin.value = DEFAULT_ROTATION_X_DEG
        rotation_y_spin.value = DEFAULT_ROTATION_Y_DEG
        rotation_z_spin.value = DEFAULT_ROTATION_Z_DEG

    button_box.accepted.connect(dialog.accept)
    button_box.rejected.connect(dialog.reject)
    reset_button.clicked.connect(reset_defaults)
    form_layout.addRow(button_box)

    if dialog.exec() != qt.QDialog.Accepted:
        return None

    markup_name = markup_name_combo.currentText.strip()
    if not markup_name:
        raise ValueError("Markup / fiducial name cannot be empty.")

    selected_index = markup_name_combo.currentIndex
    if selected_index >= 0 and markup_name == markup_name_combo.itemText(selected_index):
        selected_selector = markup_name_combo.itemData(selected_index)
        if selected_selector:
            markup_name = selected_selector

    return {
        "markup_name": markup_name,
        "guide_cannula_diameter_mm": guide_cannula_diameter_inch_spin.value * 25.4,
        "guide_cannula_length_mm": guide_cannula_length_spin.value,
        "guide_cannula_z_offset_mm": guide_cannula_offset_spin.value,
        "infusion_cannula_diameter_mm": infusion_cannula_diameter_inch_spin.value * 25.4,
        "infusion_cannula_length_mm": infusion_cannula_length_spin.value,
        "adapter_diameter_mm": adapter_diameter_spin.value,
        "adapter_height_mm": adapter_height_spin.value,
        "opacity": opacity_spin.value,
        "ambient": ambient_spin.value,
        "initial_rotation_deg": [
            rotation_x_spin.value,
            rotation_y_spin.value,
            rotation_z_spin.value,
        ],
    }


# -----------------------------------------------------------------------------
# Build geometry as a local assembly with origin at the specified fiducial.
# A single transform node places the full assembly at the fiducial and provides
# a rotation object in the Transforms module.
# -----------------------------------------------------------------------------
params = prompt_user_parameters()
if params is None:
    print("Cylinder assembly creation canceled.")
else:
    START_MARKUP_NAME = params["markup_name"]
    GUIDE_CANNULA_DIAMETER_MM = params["guide_cannula_diameter_mm"]
    GUIDE_CANNULA_LENGTH_MM = params["guide_cannula_length_mm"]
    GUIDE_CANNULA_Z_OFFSET_MM = params["guide_cannula_z_offset_mm"]
    INFUSION_CANNULA_DIAMETER_MM = params["infusion_cannula_diameter_mm"]
    INFUSION_CANNULA_LENGTH_MM = params["infusion_cannula_length_mm"]
    ADAPTER_DIAMETER_MM = params["adapter_diameter_mm"]
    ADAPTER_HEIGHT_MM = params["adapter_height_mm"]
    OPACITY = params["opacity"]
    AMBIENT = params["ambient"]
    INITIAL_ROTATION_DEG = params["initial_rotation_deg"]

    source_node, source_index, start_point = get_point_from_markup_name(START_MARKUP_NAME)

    transform_name = f"{START_MARKUP_NAME}_cylinderAssemblyTransform"
    guide_cannula_name = f"{START_MARKUP_NAME}_GuideCannula"
    infusion_cannula_name = f"{START_MARKUP_NAME}_InfusionCannula"
    adapter_name = f"{START_MARKUP_NAME}_Adapter"

    # Delete any pre-existing nodes with the same names.
    for node_name in [guide_cannula_name, infusion_cannula_name, adapter_name, transform_name]:
        remove_node_if_exists(node_name)

    assembly_transform = create_linear_transform_node(
        transform_name,
        translation_ras=start_point,
    )

    initial_rotation_transform = create_rotation_transform(INITIAL_ROTATION_DEG)

    # Local coordinates relative to the fiducial.
    # Local +Z corresponds to dorsal in the current script.
    guide_cannula_bottom_local = [0.0, 0.0, GUIDE_CANNULA_Z_OFFSET_MM]
    guide_cannula_center_local = [0.0, 0.0, GUIDE_CANNULA_Z_OFFSET_MM + GUIDE_CANNULA_LENGTH_MM / 2.0]
    guide_cannula_tip_local = [0.0, 0.0, GUIDE_CANNULA_Z_OFFSET_MM + GUIDE_CANNULA_LENGTH_MM]

    infusion_cannula_bottom_local = [0.0, 0.0, 0.0]
    infusion_cannula_center_local = [0.0, 0.0, INFUSION_CANNULA_LENGTH_MM / 2.0]
    infusion_cannula_tip_local = [0.0, 0.0, INFUSION_CANNULA_LENGTH_MM]

    adapter_center_local = guide_cannula_tip_local
    adapter_bottom_local = [0.0, 0.0, guide_cannula_tip_local[2] - ADAPTER_HEIGHT_MM / 2.0]
    adapter_top_local = [0.0, 0.0, guide_cannula_tip_local[2] + ADAPTER_HEIGHT_MM / 2.0]

    guide_cannula_bottom_local = rotate_local_point(initial_rotation_transform, guide_cannula_bottom_local)
    guide_cannula_center_local = rotate_local_point(initial_rotation_transform, guide_cannula_center_local)
    guide_cannula_tip_local = rotate_local_point(initial_rotation_transform, guide_cannula_tip_local)

    infusion_cannula_bottom_local = rotate_local_point(initial_rotation_transform, infusion_cannula_bottom_local)
    infusion_cannula_center_local = rotate_local_point(initial_rotation_transform, infusion_cannula_center_local)
    infusion_cannula_tip_local = rotate_local_point(initial_rotation_transform, infusion_cannula_tip_local)

    adapter_center_local = rotate_local_point(initial_rotation_transform, adapter_center_local)
    adapter_bottom_local = rotate_local_point(initial_rotation_transform, adapter_bottom_local)
    adapter_top_local = rotate_local_point(initial_rotation_transform, adapter_top_local)

    rotated_axis_vector = rotate_local_vector(initial_rotation_transform, [0.0, 0.0, 1.0])

    guide_cannula = add_cylinder_local(
        center_local=guide_cannula_center_local,
        axis_vector=rotated_axis_vector,
        length_mm=GUIDE_CANNULA_LENGTH_MM,
        radius_mm=GUIDE_CANNULA_DIAMETER_MM / 2.0,
        name=guide_cannula_name,
        color_rgb=SILVER,
        opacity=OPACITY,
        ambient=AMBIENT,
    )

    infusion_cannula = add_cylinder_local(
        center_local=infusion_cannula_center_local,
        axis_vector=rotated_axis_vector,
        length_mm=INFUSION_CANNULA_LENGTH_MM,
        radius_mm=INFUSION_CANNULA_DIAMETER_MM / 2.0,
        name=infusion_cannula_name,
        color_rgb=SILVER,
        opacity=OPACITY,
        ambient=AMBIENT,
    )

    adapter = add_cylinder_local(
        center_local=adapter_center_local,
        axis_vector=rotated_axis_vector,
        length_mm=ADAPTER_HEIGHT_MM,
        radius_mm=ADAPTER_DIAMETER_MM / 2.0,
        name=adapter_name,
        color_rgb=BRASS,
        opacity=OPACITY,
        ambient=AMBIENT,
    )

    # Parent all cylinders to the same transform so they rotate together.
    for model_node in [guide_cannula, infusion_cannula, adapter]:
        model_node.SetAndObserveTransformNodeID(assembly_transform.GetID())

    print(f"Start point / assembly origin: {start_point}")
    print(f"Initial rotation (deg): {INITIAL_ROTATION_DEG}")
    print(f"Transform node: {assembly_transform.GetName()}")
    print(f"GuideCannula local bottom: {guide_cannula_bottom_local}")
    print(f"GuideCannula local top / Adapter center: {guide_cannula_tip_local}")
    print(f"InfusionCannula local bottom: {infusion_cannula_bottom_local}")
    print(f"InfusionCannula local top: {infusion_cannula_tip_local}")
    print(f"Adapter local span: {adapter_bottom_local} to {adapter_top_local}")
    print(f"Created: {guide_cannula.GetName()}, {infusion_cannula.GetName()}, {adapter.GetName()}")
    print("Use the Transforms module on the assembly transform node to rotate all cylinders together.")
