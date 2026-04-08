import math
import slicer
import qt
import vtk


# exec(open(r"c:\src\helper_fnc\slicer\slicer_measure_point_distance_angle.py", encoding="utf-8").read())


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
            })

        for control_point_index in range(control_point_count):
            label = node.GetNthControlPointLabel(control_point_index) or f"Point {control_point_index}"
            options.append({
                "display_text": f"{label} ({node_name})",
                "selector": f"control_point::{node_id}::{control_point_index}",
            })

    return options


def populate_combo(combo_box, options):
    combo_box.clear()
    for option in options:
        combo_box.addItem(option["display_text"], option["selector"])


def get_current_selector(combo_box):
    return combo_box.itemData(combo_box.currentIndex)


def get_point_from_selector(selector):
    if selector.startswith("control_point::"):
        _, node_id, control_point_index = selector.split("::", 2)
        node = slicer.mrmlScene.GetNodeByID(node_id)
        if not node or not node.IsA("vtkMRMLMarkupsNode"):
            raise ValueError(f"Could not find markups node for selector '{selector}'.")

        control_point_index = int(control_point_index)
        if control_point_index < 0 or control_point_index >= node.GetNumberOfControlPoints():
            raise ValueError(f"Control point selector '{selector}' is out of range.")

        point_world = [0.0, 0.0, 0.0]
        node.GetNthControlPointPositionWorld(control_point_index, point_world)
        label = node.GetNthControlPointLabel(control_point_index) or f"Point {control_point_index}"
        return {
            "node": node,
            "control_point_index": control_point_index,
            "point_world": point_world,
            "description": f"{label} ({node.GetName()})",
        }

    if selector.startswith("node::"):
        _, node_id = selector.split("::", 1)
        node = slicer.mrmlScene.GetNodeByID(node_id)
        if not node or not node.IsA("vtkMRMLMarkupsNode"):
            raise ValueError(f"Could not find markups node for selector '{selector}'.")
        if node.GetNumberOfControlPoints() < 1:
            raise ValueError(f"Markups node '{node.GetName()}' has no control points.")

        point_world = [0.0, 0.0, 0.0]
        node.GetNthControlPointPositionWorld(0, point_world)
        label = node.GetNthControlPointLabel(0) or "Point 0"
        return {
            "node": node,
            "control_point_index": 0,
            "point_world": point_world,
            "description": f"{label} ({node.GetName()})",
        }

    raise ValueError(f"Unsupported selector '{selector}'.")


def remove_node_if_exists(node_name):
    nodes_to_remove = []
    for node in slicer.util.getNodesByClass("vtkMRMLNode"):
        if node and node.GetName() == node_name:
            nodes_to_remove.append(node)

    for node in nodes_to_remove:
        slicer.mrmlScene.RemoveNode(node)


def build_default_line_name(start_info, finish_info):
    start_name = start_info["description"].replace("[", "(").replace("]", ")")
    finish_name = finish_info["description"].replace("[", "(").replace("]", ")")
    return f"DistanceLine_{start_name}_to_{finish_name}"


def create_line_node(name, start_point, end_point, color_rgb):
    line_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLMarkupsLineNode", name)
    line_node.CreateDefaultDisplayNodes()
    line_node.AddControlPointWorld(vtk.vtkVector3d(start_point[0], start_point[1], start_point[2]))
    line_node.AddControlPointWorld(vtk.vtkVector3d(end_point[0], end_point[1], end_point[2]))

    display_node = line_node.GetDisplayNode()
    if display_node is not None:
        display_node.SetSelectedColor(color_rgb[0], color_rgb[1], color_rgb[2])
        display_node.SetColor(color_rgb[0], color_rgb[1], color_rgb[2])
        display_node.SetTextScale(0.0)
        if hasattr(display_node, "SetLineThickness"):
            display_node.SetLineThickness(0.4)

    return line_node


def compute_measurements(start_point, finish_point):
    delta_ras = [
        finish_point[0] - start_point[0],
        finish_point[1] - start_point[1],
        finish_point[2] - start_point[2],
    ]

    distance_mm = math.sqrt(sum(component * component for component in delta_ras))
    vertical_reference = abs(delta_ras[2])

    if distance_mm == 0.0:
        angle_from_vertical_y_deg = None
        angle_from_vertical_x_deg = None
        total_angle_from_vertical_deg = None
    else:
        angle_from_vertical_y_deg = math.degrees(math.atan2(delta_ras[1], vertical_reference))
        angle_from_vertical_x_deg = math.degrees(math.atan2(delta_ras[0], vertical_reference))
        cosine_value = min(1.0, max(-1.0, vertical_reference / distance_mm))
        total_angle_from_vertical_deg = math.degrees(math.acos(cosine_value))

    return {
        "delta_ras": delta_ras,
        "distance_mm": distance_mm,
        "angle_from_vertical_y_deg": angle_from_vertical_y_deg,
        "angle_from_vertical_x_deg": angle_from_vertical_x_deg,
        "total_angle_from_vertical_deg": total_angle_from_vertical_deg,
    }


def format_point(point_ras):
    return f"[{point_ras[0]:0.3f}, {point_ras[1]:0.3f}, {point_ras[2]:0.3f}]"


def format_angle(angle_deg):
    if angle_deg is None:
        return "N/A"
    return f"{angle_deg:0.3f}"


def prompt_user_parameters():
    markup_options = get_available_markup_options()
    if len(markup_options) < 2:
        raise ValueError("At least two markup nodes or control points are required.")

    dialog = qt.QDialog(slicer.util.mainWindow())
    dialog.setWindowTitle("Measure Point Distance and Angle")
    form_layout = qt.QFormLayout(dialog)

    info_label = qt.QLabel(
        "Select two points. The script measures 3D distance and the signed angle from vertical (Z/IS) in the Y/AP and X/LR planes."
    )
    info_label.wordWrap = True

    start_combo = qt.QComboBox()
    start_combo.setInsertPolicy(qt.QComboBox.NoInsert)
    populate_combo(start_combo, markup_options)

    finish_combo = qt.QComboBox()
    finish_combo.setInsertPolicy(qt.QComboBox.NoInsert)
    populate_combo(finish_combo, markup_options)
    finish_combo.setCurrentIndex(1)

    draw_line_checkbox = qt.QCheckBox("Draw line between selected points")
    draw_line_checkbox.checked = True

    line_name_edit = qt.QLineEdit()

    def update_line_name(*_args):
        start_info = get_point_from_selector(get_current_selector(start_combo))
        finish_info = get_point_from_selector(get_current_selector(finish_combo))
        line_name_edit.setText(build_default_line_name(start_info, finish_info))

    start_combo.currentIndexChanged.connect(update_line_name)
    finish_combo.currentIndexChanged.connect(update_line_name)
    draw_line_checkbox.toggled.connect(line_name_edit.setEnabled)
    update_line_name()
    line_name_edit.setEnabled(draw_line_checkbox.checked)

    form_layout.addRow(info_label)
    form_layout.addRow("Point 1:", start_combo)
    form_layout.addRow("Point 2:", finish_combo)
    form_layout.addRow("", draw_line_checkbox)
    form_layout.addRow("Line node name:", line_name_edit)

    button_box = qt.QDialogButtonBox()
    button_box.setStandardButtons(qt.QDialogButtonBox.Ok | qt.QDialogButtonBox.Cancel)
    button_box.accepted.connect(dialog.accept)
    button_box.rejected.connect(dialog.reject)
    form_layout.addRow(button_box)

    if dialog.exec() != qt.QDialog.Accepted:
        return None

    return {
        "start_selector": get_current_selector(start_combo),
        "finish_selector": get_current_selector(finish_combo),
        "draw_line": draw_line_checkbox.checked,
        "line_name": line_name_edit.text.strip(),
    }


def show_results_dialog(start_info, finish_info, measurements, line_node=None):
    dialog = qt.QDialog(slicer.util.mainWindow())
    dialog.setWindowTitle("Point Distance and Angle")
    dialog_layout = qt.QVBoxLayout(dialog)

    header_label = qt.QLabel(
        f"Point 1: {start_info['description']}\nPoint 2: {finish_info['description']}"
    )
    header_label.wordWrap = True
    dialog_layout.addWidget(header_label)

    table_widget = qt.QTableWidget(3, 4)
    table_widget.setHorizontalHeaderLabels(["Measurement", "X (LR)", "Y (AP)", "Z (IS)"])
    table_widget.verticalHeader().setVisible(False)
    table_widget.setEditTriggers(qt.QAbstractItemView.NoEditTriggers)
    table_widget.setSelectionMode(qt.QAbstractItemView.NoSelection)
    table_widget.setAlternatingRowColors(True)

    table_rows = [
        ("Point 1 position (mm)", start_info["point_world"]),
        ("Point 2 position (mm)", finish_info["point_world"]),
        ("Point 1 to Point 2 delta (mm)", measurements["delta_ras"]),
    ]

    for row_index, (label, values) in enumerate(table_rows):
        table_widget.setItem(row_index, 0, qt.QTableWidgetItem(label))
        table_widget.setItem(row_index, 1, qt.QTableWidgetItem(f"{values[0]:0.3f}"))
        table_widget.setItem(row_index, 2, qt.QTableWidgetItem(f"{values[1]:0.3f}"))
        table_widget.setItem(row_index, 3, qt.QTableWidgetItem(f"{values[2]:0.3f}"))

    table_widget.resizeColumnsToContents()
    table_widget.horizontalHeader().setSectionResizeMode(0, qt.QHeaderView.Stretch)
    dialog_layout.addWidget(table_widget)

    summary_lines = [
        f"3D distance (mm): {measurements['distance_mm']:0.3f}",
        "Angle from vertical in Y (AP) plane (deg): "
        f"{format_angle(measurements['angle_from_vertical_y_deg'])}",
        "Angle from vertical in X (LR) plane (deg): "
        f"{format_angle(measurements['angle_from_vertical_x_deg'])}",
        "Overall angle from vertical (deg): "
        f"{format_angle(measurements['total_angle_from_vertical_deg'])}",
        "Angles are signed using Point 1 -> Point 2, with positive values toward +Y (A) and +X (R).",
    ]

    if line_node is not None:
        summary_lines.append(f"Created line node: {line_node.GetName()}")

    summary_label = qt.QLabel("\n".join(summary_lines))
    summary_label.wordWrap = True
    dialog_layout.addWidget(summary_label)

    button_box = qt.QDialogButtonBox(qt.QDialogButtonBox.Ok)
    button_box.accepted.connect(dialog.accept)
    dialog_layout.addWidget(button_box)
    dialog.exec()


params = prompt_user_parameters()
if params is None:
    print("Distance and angle measurement cancelled.")
else:
    start_info = get_point_from_selector(params["start_selector"])
    finish_info = get_point_from_selector(params["finish_selector"])
    measurements = compute_measurements(start_info["point_world"], finish_info["point_world"])

    line_node = None
    if params["draw_line"]:
        line_name = params["line_name"] or build_default_line_name(start_info, finish_info)
        remove_node_if_exists(line_name)
        line_node = create_line_node(
            line_name,
            start_info["point_world"],
            finish_info["point_world"],
            (0.90, 0.75, 0.15),
        )

    result_lines = [
        f"Point 1: {start_info['description']}",
        f"Point 2: {finish_info['description']}",
        f"Point 1 position RAS (mm): {format_point(start_info['point_world'])}",
        f"Point 2 position RAS (mm): {format_point(finish_info['point_world'])}",
        f"Point 1 -> Point 2 delta RAS (mm): {format_point(measurements['delta_ras'])}",
        f"3D distance (mm): {measurements['distance_mm']:0.3f}",
        "Angle from vertical in Y (AP) plane (deg): "
        f"{format_angle(measurements['angle_from_vertical_y_deg'])}",
        "Angle from vertical in X (LR) plane (deg): "
        f"{format_angle(measurements['angle_from_vertical_x_deg'])}",
        "Overall angle from vertical (deg): "
        f"{format_angle(measurements['total_angle_from_vertical_deg'])}",
    ]

    if line_node is not None:
        result_lines.append(f"Created line node: {line_node.GetName()}")

    result_text = "\n".join(result_lines)
    print(result_text)
    show_results_dialog(start_info, finish_info, measurements, line_node)