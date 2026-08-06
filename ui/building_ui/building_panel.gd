class_name BuildingPanel
extends FloatingPanel

var building: Building
var world_blocks: WorldBlockLayer
var selected_cell := WorldBlockLayer.INVALID_CELL
var renaming := false

@onready var building_name_input: LineEdit = $BuildingName
@onready var building_info_label: RichTextLabel = $BuildingInfo


func _ready() -> void:
	hide()


func open_for_building(
	new_building: Building,
	new_world_blocks: WorldBlockLayer,
	cell: Vector2i
) -> void:
	_finish_rename()
	_disconnect_world_layer()
	building = new_building
	world_blocks = new_world_blocks
	selected_cell = cell
	if world_blocks != null:
		world_blocks.buildings_rebuilt.connect(_on_buildings_rebuilt)
	refresh_information()
	show()
	move_to_front()


func close_panel() -> void:
	_finish_rename()
	hide()
	_disconnect_world_layer()
	building = null
	world_blocks = null
	selected_cell = WorldBlockLayer.INVALID_CELL


func is_building_selected(candidate: Building) -> bool:
	return visible and building != null and building == candidate


func refresh_information() -> void:
	if building == null:
		if not renaming:
			building_name_input.text = "No building selected"
		building_info_label.text = (
			"Type: --\n"
			+ "Blocks: --\n"
			+ "Owner: --"
		)
		return
	if not renaming:
		building_name_input.text = building.building_name
	var details: Array[String] = [
		"Type: %s" % (
			"Vehicle Workshop"
			if building.is_vehicle_workshop()
			else "Building"
		),
		"Blocks: %d" % building.block_anchors.size(),
		"Owner: %s" % String(building.owner_id),
	]
	var control_text := _get_control_text(building.block_assembly)
	if not control_text.is_empty():
		details.append("Control: %s" % control_text)
	building_info_label.text = "\n".join(details)


func _get_control_text(assembly: BlockAssembly) -> String:
	if assembly == null or assembly.control_blocks.is_empty():
		return ""
	if is_instance_valid(assembly.active_control_block):
		return BlockDB.get_block_name(assembly.active_control_block.block_id)
	return "No active control"


func _start_rename() -> void:
	if building == null:
		return
	renaming = true
	building_name_input.editable = true
	building_name_input.grab_focus()
	building_name_input.select_all()


func _finish_rename() -> void:
	if not renaming:
		return
	renaming = false
	if building != null:
		var new_name := building_name_input.text.strip_edges()
		if not new_name.is_empty():
			building.building_name = new_name
	building_name_input.editable = false
	building_name_input.release_focus()
	refresh_information()


func _on_rename_button_pressed() -> void:
	if renaming:
		_finish_rename()
	else:
		_start_rename()


func _on_name_text_submitted(_new_text: String) -> void:
	_finish_rename()


func _on_name_focus_exited() -> void:
	_finish_rename()


func _on_buildings_rebuilt(_rebuilt: Array[Building]) -> void:
	if world_blocks == null:
		close_panel()
		return
	var current := world_blocks.get_building_at(selected_cell)
	if current == null:
		close_panel()
		return
	building = current
	refresh_information()


func _disconnect_world_layer() -> void:
	if (
		world_blocks != null
		and world_blocks.buildings_rebuilt.is_connected(
			_on_buildings_rebuilt
		)
	):
		world_blocks.buildings_rebuilt.disconnect(_on_buildings_rebuilt)


func _on_close_button_pressed() -> void:
	close_panel()
