class_name VehiclePanel
extends FloatingPanel

var vehicle: Vehicle
var docked_maintenance_bay: MaintenanceBayBlock
var renaming := false

@onready var vehicle_name_input: LineEdit = $VehicleName
@onready var vehicle_info_label: RichTextLabel = $VehicleInfo
@onready var edit_button: TextureButton = $EditButton


func _ready() -> void:
	hide()


func _process(_delta: float) -> void:
	if vehicle != null and not is_instance_valid(vehicle):
		close_panel()
		return
	if visible:
		refresh_information()


func open_for_vehicle(new_vehicle: Vehicle) -> void:
	if not is_instance_valid(new_vehicle):
		return
	_finish_rename()
	vehicle = new_vehicle
	refresh_information()
	show()
	move_to_front()


func close_panel() -> void:
	_finish_rename()
	hide()
	vehicle = null


func is_vehicle_selected(candidate: Vehicle) -> bool:
	return visible and is_instance_valid(vehicle) and vehicle == candidate


func refresh_information() -> void:
	if not is_instance_valid(vehicle):
		docked_maintenance_bay = null
		edit_button.hide()
		if not renaming:
			vehicle_name_input.text = "No vehicle selected"
		vehicle_info_label.text = (
			"Blocks: --\n"
			+ "Owner: --\n"
			+ "Max engine power: --\n"
			+ "Speed: --\n"
			+ "Weight: --"
		)
		return
	if not renaming:
		vehicle_name_input.text = vehicle.vehicle_name
	docked_maintenance_bay = _find_docked_maintenance_bay(vehicle)
	edit_button.visible = is_instance_valid(docked_maintenance_bay)
	var details: Array[String] = [
		"Blocks: %d" % vehicle.blocks.size(),
		"Owner: %s" % String(vehicle.owner_id),
	]
	var control_text := _get_control_text(vehicle.block_assembly)
	if not control_text.is_empty():
		details.append("Control: %s" % control_text)
	details.append(
		"Max engine power: %.0f"
		% vehicle.block_assembly.get_max_engine_power()
	)
	details.append(
		"Speed: %.1f tiles/s"
		% (vehicle.linear_velocity.length() / Globals.TILE_SIZE)
	)
	details.append("Weight: %.1f t" % vehicle.total_mass)
	vehicle_info_label.text = "\n".join(details)


func _get_control_text(assembly: BlockAssembly) -> String:
	if assembly == null or assembly.control_blocks.is_empty():
		return ""
	if is_instance_valid(assembly.active_control_block):
		return BlockDB.get_block_name(assembly.active_control_block.block_id)
	return "No active control"


func _find_docked_maintenance_bay(
	target_vehicle: Vehicle
) -> MaintenanceBayBlock:
	if not is_instance_valid(target_vehicle):
		return null
	if (
		is_instance_valid(docked_maintenance_bay)
		and docked_maintenance_bay.get_docked_vehicle() == target_vehicle
	):
		return docked_maintenance_bay
	for node: Node in get_tree().get_nodes_in_group("world_block_layers"):
		var world_layer := node as WorldBlockLayer
		if world_layer == null:
			continue
		for building: Building in world_layer.buildings:
			var maintenance_bay := building.get_maintenance_bay_for_vehicle(
				target_vehicle
			)
			if maintenance_bay != null:
				return maintenance_bay
	return null


func _start_rename() -> void:
	if not is_instance_valid(vehicle):
		return
	renaming = true
	vehicle_name_input.editable = true
	vehicle_name_input.grab_focus()
	vehicle_name_input.select_all()


func _finish_rename() -> void:
	if not renaming:
		return
	renaming = false
	if is_instance_valid(vehicle):
		var new_name := vehicle_name_input.text.strip_edges()
		if not new_name.is_empty():
			vehicle.vehicle_name = new_name
	vehicle_name_input.editable = false
	vehicle_name_input.release_focus()
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


func _on_edit_button_pressed() -> void:
	if not is_instance_valid(vehicle):
		return
	var maintenance_bay := _find_docked_maintenance_bay(vehicle)
	if maintenance_bay == null:
		refresh_information()
		return
	var editor := get_tree().get_first_node_in_group(
		"vehicle_editor"
	) as VehicleEditor
	if editor == null:
		return
	editor.set_workshop_context(maintenance_bay, vehicle)
	var result := editor.begin_workshop_edit(maintenance_bay, vehicle)
	if bool(result.get("ok", false)):
		close_panel()


func _on_close_button_pressed() -> void:
	close_panel()
