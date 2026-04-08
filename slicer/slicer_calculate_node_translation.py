import slicer
import qt
import vtk


# exec(open(r"c:\src\helper_fnc\slicer\slicer_calculate_node_translation.py", encoding="utf-8").read())


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


def create_translation_transform_node(name, translation_ras):
    transform_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLinearTransformNode", name)
    matrix = vtk.vtkMatrix4x4()
    matrix.Identity()
    matrix.SetElement(0, 3, translation_ras[0])
    matrix.SetElement(1, 3, translation_ras[1])
    matrix.SetElement(2, 3, translation_ras[2])
    transform_node.SetMatrixTransformToParent(matrix)
    return transform_node


def create_line_node(name, start_point, end_point, color_rgb):
    line_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLMarkupsLineNode", name)
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


def recreate_subject_hierarchy_folder(folder_name):
    subject_hierarchy_node = slicer.vtkMRMLSubjectHierarchyNode.GetSubjectHierarchyNode(slicer.mrmlScene)
    existing_item_id = subject_hierarchy_node.GetItemByName(folder_name)
    if existing_item_id:
        subject_hierarchy_node.RemoveItem(existing_item_id)

    return subject_hierarchy_node, subject_hierarchy_node.CreateFolderItem(
        subject_hierarchy_node.GetSceneItemID(),
        folder_name,
    )


def create_axis_translation_lines(start_point, finish_point, prefix_name):
    intermediate_x = [finish_point[0], start_point[1], start_point[2]]
    intermediate_xy = [finish_point[0], finish_point[1], start_point[2]]
    folder_name = f"{prefix_name}_Lines"

    line_specs = [
        (f"{prefix_name}_X_LR", start_point, intermediate_x, (0.85, 0.20, 0.20)),
        (f"{prefix_name}_Y_AP", intermediate_x, intermediate_xy, (0.20, 0.65, 0.20)),
        (f"{prefix_name}_Z_IS", intermediate_xy, finish_point, (0.20, 0.35, 0.85)),
    ]

    subject_hierarchy_node, folder_item_id = recreate_subject_hierarchy_folder(folder_name)
    created_nodes = []
    for line_name, line_start, line_end, color_rgb in line_specs:
        remove_node_if_exists(line_name)
        line_node = create_line_node(line_name, line_start, line_end, color_rgb)
        line_item_id = subject_hierarchy_node.GetItemByDataNode(line_node)
        subject_hierarchy_node.SetItemParent(line_item_id, folder_item_id)
        created_nodes.append(line_node)

    return created_nodes, folder_name


def build_default_transform_name(start_info, finish_info):
    start_name = start_info["description"].replace("[", "(").replace("]", ")")
    finish_name = finish_info["description"].replace("[", "(").replace("]", ")")
    return f"Translate_{start_name}_to_{finish_name}"


def populate_combo(combo_box, options):
    combo_box.clear()
    for option in options:
        combo_box.addItem(option["display_text"], option["selector"])


def get_current_selector(combo_box):
    return combo_box.itemData(combo_box.currentIndex)


def prompt_user_parameters():
    markup_options = get_available_markup_options()
    if len(markup_options) < 2:
        raise ValueError("At least two markup nodes or control points are required.")

    dialog = qt.QDialog(slicer.util.mainWindow())
    dialog.setWindowTitle("Calculate Node Translation")
    form_layout = qt.QFormLayout(dialog)

    info_label = qt.QLabel(
        "Select a start point and finish point. The script will calculate the translation in RAS coordinates."
    )
    info_label.wordWrap = True

    start_combo = qt.QComboBox()
    start_combo.setInsertPolicy(qt.QComboBox.NoInsert)
    populate_combo(start_combo, markup_options)

    finish_combo = qt.QComboBox()
    finish_combo.setInsertPolicy(qt.QComboBox.NoInsert)
    populate_combo(finish_combo, markup_options)
    finish_combo.setCurrentIndex(1)

    create_transform_checkbox = qt.QCheckBox("Create linear transform node")
    create_transform_checkbox.checked = False

    draw_lines_checkbox = qt.QCheckBox("Draw axis-aligned translation lines")
    draw_lines_checkbox.checked = False

    transform_name_edit = qt.QLineEdit()

    def update_transform_name(*_args):
        start_info = get_point_from_selector(get_current_selector(start_combo))
        finish_info = get_point_from_selector(get_current_selector(finish_combo))
        transform_name_edit.setText(build_default_transform_name(start_info, finish_info))

    start_combo.currentIndexChanged.connect(update_transform_name)
    finish_combo.currentIndexChanged.connect(update_transform_name)
    create_transform_checkbox.toggled.connect(transform_name_edit.setEnabled)
    update_transform_name()
    transform_name_edit.setEnabled(create_transform_checkbox.checked)

    form_layout.addRow(info_label)
    form_layout.addRow("Start node:", start_combo)
    form_layout.addRow("Finish node:", finish_combo)
    form_layout.addRow("", create_transform_checkbox)
    form_layout.addRow("", draw_lines_checkbox)
    form_layout.addRow("Transform node name:", transform_name_edit)

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
        "create_transform": create_transform_checkbox.checked,
        "draw_lines": draw_lines_checkbox.checked,
        "transform_name": transform_name_edit.text.strip(),
    }


def format_point(point_ras):
    return f"[{point_ras[0]:0.3f}, {point_ras[1]:0.3f}, {point_ras[2]:0.3f}]"


def show_results_dialog(
    start_info,
    finish_info,
    translation_ras,
    transform_node=None,
    line_nodes=None,
    line_folder_name=None,
):
    dialog = qt.QDialog(slicer.util.mainWindow())
    dialog.setWindowTitle("Node Translation")
    dialog_layout = qt.QVBoxLayout(dialog)

    header_label = qt.QLabel(
        f"Start: {start_info['description']}\nFinish: {finish_info['description']}"
    )
    dialog_layout.addWidget(header_label)

    table_widget = qt.QTableWidget(3, 4)
    table_widget.setHorizontalHeaderLabels(["Measurement", "X (LR)", "Y (AP)", "Z (IS)"])
    table_widget.verticalHeader().setVisible(False)
    table_widget.setEditTriggers(qt.QAbstractItemView.NoEditTriggers)
    table_widget.setSelectionMode(qt.QAbstractItemView.NoSelection)
    table_widget.setAlternatingRowColors(True)

    table_rows = [
        ("Start position (mm)", start_info["point_world"]),
        ("Finish position (mm)", finish_info["point_world"]),
        ("Required translation (mm)", translation_ras),
    ]

    for row_index, (label, values) in enumerate(table_rows):
        table_widget.setItem(row_index, 0, qt.QTableWidgetItem(label))
        table_widget.setItem(row_index, 1, qt.QTableWidgetItem(f"{values[0]:0.3f}"))
        table_widget.setItem(row_index, 2, qt.QTableWidgetItem(f"{values[1]:0.3f}"))
        table_widget.setItem(row_index, 3, qt.QTableWidgetItem(f"{values[2]:0.3f}"))

    table_widget.resizeColumnsToContents()
    table_widget.horizontalHeader().setStretchLastSection(False)
    table_widget.horizontalHeader().setSectionResizeMode(0, qt.QHeaderView.Stretch)
    dialog_layout.addWidget(table_widget)

    if transform_node is not None:
        transform_label = qt.QLabel(f"Created transform node: {transform_node.GetName()}")
        dialog_layout.addWidget(transform_label)

    if line_nodes:
        if line_folder_name:
            folder_label = qt.QLabel(f"Created line folder: {line_folder_name}")
            dialog_layout.addWidget(folder_label)

        line_names = ", ".join(node.GetName() for node in line_nodes)
        lines_label = qt.QLabel(f"Created line nodes: {line_names}")
        lines_label.wordWrap = True
        dialog_layout.addWidget(lines_label)

    button_box = qt.QDialogButtonBox(qt.QDialogButtonBox.Ok)
    button_box.accepted.connect(dialog.accept)
    dialog_layout.addWidget(button_box)
    dialog.exec()


params = prompt_user_parameters()
if params is None:
    print("Translation calculation cancelled.")
else:
    start_info = get_point_from_selector(params["start_selector"])
    finish_info = get_point_from_selector(params["finish_selector"])

    translation_ras = [
        finish_info["point_world"][0] - start_info["point_world"][0],
        finish_info["point_world"][1] - start_info["point_world"][1],
        finish_info["point_world"][2] - start_info["point_world"][2],
    ]

    transform_node = None
    if params["create_transform"]:
        transform_name = params["transform_name"] or build_default_transform_name(start_info, finish_info)
        remove_node_if_exists(transform_name)
        transform_node = create_translation_transform_node(transform_name, translation_ras)

    line_nodes = None
    line_folder_name = None
    if params["draw_lines"]:
        line_prefix = params["transform_name"] or build_default_transform_name(start_info, finish_info)
        line_nodes, line_folder_name = create_axis_translation_lines(
            start_info["point_world"],
            finish_info["point_world"],
            line_prefix,
        )

    result_lines = [
        f"Start: {start_info['description']}",
        f"Finish: {finish_info['description']}",
        f"Start position RAS (mm): {format_point(start_info['point_world'])}",
        f"Finish position RAS (mm): {format_point(finish_info['point_world'])}",
        f"Required translation RAS (mm): {format_point(translation_ras)}",
    ]

    if transform_node is not None:
        result_lines.append(f"Created transform node: {transform_node.GetName()}")

    if line_nodes:
        if line_folder_name:
            result_lines.append(f"Created line folder: {line_folder_name}")

        result_lines.append(
            "Created line nodes: " + ", ".join(line_node.GetName() for line_node in line_nodes)
        )

    result_text = "\n".join(result_lines)
    print(result_text)
    show_results_dialog(
        start_info,
        finish_info,
        translation_ras,
        transform_node,
        line_nodes,
        line_folder_name,
    )