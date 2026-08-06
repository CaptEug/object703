class_name VehicleEditor
extends Control

signal workshop_session_changed(active: bool)
signal status_changed(message: String)

enum InterfaceState {
	CLOSED,
	EDIT,
}

enum EditMode {
	BUILD,
	DISMANTLE,
}

enum BlueprintDialogMode {
	NONE,
	SAVE,
	LOAD,
}

const DOCKING_LINEAR_SPEED_LIMIT := 2.0
const DOCKING_ANGULAR_SPEED_LIMIT := 0.05

var vehicle: Vehicle
var selected_block: Block
var preview_cell: Vector2i
var preview_block: Block
var preview_rotation := 0
var interface_state := InterfaceState.CLOSED
var edit_mode := EditMode.BUILD
var blueprint_dialog_mode := BlueprintDialogMode.NONE
var new_vehicle_index := 1
var active_workshop: MaintenanceBayBlock
var active_workshop_building: Building
var workshop_context: MaintenanceBayBlock
var workshop_context_vehicle: Vehicle
var workshop_new_vehicle := false
var _session_previous_freeze := false
var _session_previous_camera_rotation := 0.0
var removal_hover: RemovalHoverOverlay

@onready var editor_dock: Panel = $EditorDock
@onready var palette: BlockPalette = (
	$EditorDock/PaletteArea/Panel/Clipper/BlockPalette
)
@onready var com_icon: Sprite2D = $COMicon
@onready var com_button: CheckButton = $EditorDock/EditorTools/CoMButton
@onready var blueprint_dialog: FileDialog = $BlueprintDialog

@export var gamemap: GameMap

var vehicle_scene: PackedScene = load("res://vehicle/Vehicle.tscn")

@export_range(1.0, 64.0, 1.0) var construction_range_tiles := 8.0


func _ready() -> void:
	add_to_group("vehicle_editor")
	ensure_removal_hover()
	set_selected_vehicle(null)
	_apply_interface_state()


func _exit_tree() -> void:
	if is_instance_valid(removal_hover):
		removal_hover.queue_free()


func _process(_delta: float) -> void:
	if vehicle != null and not is_instance_valid(vehicle):
		if active_workshop != null:
			cancel_workshop_edit("Edited vehicle is no longer available")
		else:
			set_selected_vehicle(null)
	if active_workshop != null and not is_instance_valid(active_workshop):
		cancel_workshop_edit("Maintenance bay is no longer available")
	elif (
		is_instance_valid(active_workshop)
		and _get_workshop_building(active_workshop)
		!= active_workshop_building
	):
		cancel_workshop_edit("Vehicle workshop changed")
	selected_block = palette.selected_block
	if is_editing_vehicle():
		update_preview()
	else:
		clear_preview_block()
		clear_removal_hover()
	if (
		is_editing_vehicle()
		and is_instance_valid(vehicle)
		and com_button.button_pressed
	):
		com_icon.position = world_to_screen(
			vehicle.to_global(vehicle.center_of_mass)
		)


func _unhandled_input(event: InputEvent) -> void:
	var constructor := get_tree().get_first_node_in_group(
		"building_constructor"
	) as BuildingConstructor
	if constructor != null and constructor.is_active():
		return
	if is_editing_vehicle():
		_handle_editor_input(event)


func _handle_editor_input(event: InputEvent) -> void:
	if event.is_action_pressed("ROTATE"):
		if (
			selected_block != null
			and BlockDB.is_rotatable(selected_block.block_id)
		):
			preview_rotation = wrapi(preview_rotation + 1, 0, 4)
		else:
			preview_rotation = 0
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_X:
		toggle_mode()
		return
	if not event is InputEventMouseButton or not event.pressed:
		return

	if event.button_index == MOUSE_BUTTON_RIGHT:
		if edit_mode == EditMode.BUILD:
			palette.selected_block = null
		else:
			set_mode(EditMode.BUILD)
		get_viewport().set_input_as_handled()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	var clicked_vehicle := _get_vehicle_under_mouse()
	if clicked_vehicle != null and clicked_vehicle != vehicle:
		get_viewport().set_input_as_handled()
		return
	if not is_instance_valid(vehicle):
		return
	if edit_mode == EditMode.BUILD:
		place_block()
	else:
		remove_block()
	get_viewport().set_input_as_handled()


func enter_edit_mode() -> void:
	if not is_instance_valid(vehicle) or not is_instance_valid(active_workshop):
		return
	vehicle.ensure_blueprint_from_blocks()
	vehicle.set_blueprint_ghosts_visible(true)
	interface_state = InterfaceState.EDIT
	_apply_interface_state()


func exit_edit_mode() -> void:
	clear_preview_block()
	clear_removal_hover()
	if is_instance_valid(vehicle):
		vehicle.set_blueprint_ghosts_visible(false)
	interface_state = InterfaceState.CLOSED
	_apply_interface_state()


func close_editor() -> void:
	if active_workshop != null:
		cancel_workshop_edit("Maintenance bay editing cancelled")
	clear_preview_block()
	clear_removal_hover()
	palette.selected_block = null
	if is_instance_valid(vehicle):
		vehicle.set_blueprint_ghosts_visible(false)
	interface_state = InterfaceState.CLOSED
	set_selected_vehicle(null)
	_apply_interface_state()


func is_editing_vehicle() -> bool:
	return interface_state == InterfaceState.EDIT


func is_fire_suppressed() -> bool:
	return is_editing_vehicle()


func set_workshop_context(
	workshop: MaintenanceBayBlock,
	target_vehicle: Vehicle = null
) -> void:
	workshop_context = workshop if is_instance_valid(workshop) else null
	workshop_context_vehicle = (
		target_vehicle if is_instance_valid(target_vehicle) else null
	)


func clear_workshop_context(workshop: MaintenanceBayBlock) -> void:
	if workshop_context != workshop or active_workshop == workshop:
		return
	workshop_context = null
	workshop_context_vehicle = null


func try_toggle_workshop_context() -> bool:
	if active_workshop != null:
		finish_workshop_edit()
		return true
	var target_workshop := workshop_context
	var target_vehicle := workshop_context_vehicle
	if (
		not is_instance_valid(target_workshop)
		and is_instance_valid(vehicle)
	):
		target_workshop = _find_workshop_for_vehicle(vehicle)
		target_vehicle = vehicle
	if not is_instance_valid(target_workshop):
		return false
	if not is_instance_valid(target_vehicle):
		return false
	begin_workshop_edit(target_workshop, target_vehicle)
	return true


func begin_workshop_edit(
	workshop: MaintenanceBayBlock,
	target_vehicle: Vehicle
) -> Dictionary:
	if active_workshop != null:
		return _session_error("Another maintenance bay session is already active")
	if not is_instance_valid(workshop) or not is_instance_valid(target_vehicle):
		return _session_error("Maintenance bay or vehicle is unavailable")
	var building := _get_workshop_building(workshop)
	if building == null:
		return _session_error("Vehicle workshop is unavailable")
	if target_vehicle.owner_id != building.owner_id:
		return _session_error("Vehicle owner does not match vehicle workshop owner")
	if workshop.get_docked_vehicle() != target_vehicle:
		return _session_error("Vehicle is not docked in this maintenance bay")
	if target_vehicle.linear_velocity.length() > DOCKING_LINEAR_SPEED_LIMIT:
		return _session_error("Vehicle must stop before editing")
	if absf(target_vehicle.angular_velocity) > DOCKING_ANGULAR_SPEED_LIMIT:
		return _session_error("Vehicle must stop rotating before editing")
	if not workshop.is_vehicle_fully_inside(target_vehicle):
		return _session_error("Vehicle is not fully inside this maintenance bay")
	_start_workshop_session(workshop, building, target_vehicle, false)
	return {"ok": true, "message": "Vehicle editing started"}


func begin_new_workshop_vehicle(workshop: MaintenanceBayBlock) -> Dictionary:
	if active_workshop != null:
		return _session_error("Another maintenance bay session is already active")
	if not is_instance_valid(workshop):
		return _session_error("Maintenance bay is unavailable")
	var building := _get_workshop_building(workshop)
	if building == null:
		return _session_error("Vehicle workshop is unavailable")
	if is_instance_valid(workshop.get_docked_vehicle()):
		return _session_error("Maintenance bay already has a docked vehicle")
	create_new_vehicle(workshop.get_center_world_position(), false)
	if not is_instance_valid(vehicle):
		return _session_error("New vehicle could not be created")
	vehicle.owner_id = building.owner_id
	vehicle.global_rotation = workshop.get_vehicle_front_rotation()
	workshop.track_candidate_vehicle(vehicle)
	_start_workshop_session(workshop, building, vehicle, true)
	return {"ok": true, "message": "New vehicle construction started"}


func finish_workshop_edit() -> Dictionary:
	if active_workshop == null:
		return _session_error("No maintenance bay editing session is active")
	if not is_instance_valid(vehicle):
		cancel_workshop_edit("Edited vehicle is unavailable")
		return _session_error("Edited vehicle is unavailable")
	if vehicle.blocks.is_empty():
		return _session_error("Add at least one block before finishing")
	if (
		is_instance_valid(active_workshop)
		and not active_workshop.is_vehicle_layout_inside(vehicle)
	):
		return _session_error("Vehicle must remain inside the maintenance bay")
	vehicle.normalize_layout_to_top_left()
	var finished_vehicle := vehicle
	active_workshop.track_candidate_vehicle(finished_vehicle)
	exit_edit_mode()
	_release_session_vehicle(finished_vehicle)
	_clear_active_workshop_session()
	set_selected_vehicle(finished_vehicle)
	return {"ok": true, "message": "Vehicle editing finished"}


func cancel_workshop_edit(
	message: String = "Maintenance bay editing cancelled"
) -> void:
	if active_workshop == null:
		return
	var cancelled_vehicle := vehicle
	var remove_vehicle := workshop_new_vehicle
	var session_workshop := active_workshop
	exit_edit_mode()
	if is_instance_valid(cancelled_vehicle):
		if remove_vehicle:
			session_workshop.untrack_candidate_vehicle(cancelled_vehicle)
			cancelled_vehicle.queue_free()
		else:
			_release_session_vehicle(cancelled_vehicle)
	_clear_active_workshop_session()
	if remove_vehicle:
		set_selected_vehicle(null)
	_show_status(message)


func refresh_workshop_camera() -> void:
	if not is_instance_valid(active_workshop) or not is_instance_valid(vehicle):
		return
	var camera := get_viewport().get_camera_2d()
	if camera != null and camera.has_method("focus_on_workshop_vehicle"):
		var front_rotation := (
			active_workshop.get_vehicle_front_rotation()
			if workshop_new_vehicle
			else active_workshop.get_editor_front_rotation(vehicle)
		)
		camera.call("focus_on_workshop_vehicle", vehicle, front_rotation)


func _start_workshop_session(
	workshop: MaintenanceBayBlock,
	building: Building,
	target_vehicle: Vehicle,
	is_new_vehicle: bool
) -> void:
	var constructor := get_tree().get_first_node_in_group(
		"building_constructor"
	) as BuildingConstructor
	if constructor != null:
		constructor.set_active(false)
	active_workshop = workshop
	active_workshop_building = building
	workshop_new_vehicle = is_new_vehicle
	set_workshop_context(workshop, target_vehicle)
	set_selected_vehicle(target_vehicle)
	_session_previous_freeze = target_vehicle.freeze
	var camera := get_viewport().get_camera_2d()
	_session_previous_camera_rotation = (
		camera.global_rotation if camera != null else 0.0
	)
	target_vehicle.linear_velocity = Vector2.ZERO
	target_vehicle.angular_velocity = 0.0
	target_vehicle.freeze = true
	enter_edit_mode()
	refresh_workshop_camera()
	workshop_session_changed.emit(true)


func _release_session_vehicle(target_vehicle: Vehicle) -> void:
	target_vehicle.linear_velocity = Vector2.ZERO
	target_vehicle.angular_velocity = 0.0
	target_vehicle.freeze = _session_previous_freeze
	target_vehicle.sleeping = true


func _clear_active_workshop_session() -> void:
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		camera.set("target_rot", _session_previous_camera_rotation)
	active_workshop = null
	active_workshop_building = null
	workshop_new_vehicle = false
	workshop_session_changed.emit(false)


func _get_workshop_building(workshop: MaintenanceBayBlock) -> Building:
	if not is_instance_valid(workshop):
		return null
	var world_layer := workshop.block_host as WorldBlockLayer
	if world_layer == null:
		return null
	var building := world_layer.get_building_at(workshop.origin_cell)
	if (
		building == null
		or building.get_maintenance_bay_for_block(workshop) == null
	):
		return null
	return building


func _find_workshop_for_vehicle(target_vehicle: Vehicle) -> MaintenanceBayBlock:
	if not is_instance_valid(target_vehicle):
		return null
	for node: Node in get_tree().get_nodes_in_group("world_block_layers"):
		var world_layer := node as WorldBlockLayer
		if world_layer == null:
			continue
		for building: Building in world_layer.buildings:
			var workshop := building.get_maintenance_bay_for_vehicle(
				target_vehicle
			)
			if workshop != null:
				return workshop
	return null


func _session_error(message: String) -> Dictionary:
	_show_status(message)
	return {"ok": false, "message": message}


func _apply_interface_state() -> void:
	editor_dock.visible = is_editing_vehicle()
	if is_editing_vehicle():
		editor_dock.anchor_right = 1.0
		editor_dock.offset_right = 0.0
	com_icon.visible = (
		is_editing_vehicle()
		and is_instance_valid(vehicle)
		and com_button.button_pressed
	)


func toggle_mode() -> void:
	if edit_mode == EditMode.BUILD:
		set_mode(EditMode.DISMANTLE)
	else:
		set_mode(EditMode.BUILD)


func set_mode(new_mode: EditMode) -> void:
	if edit_mode == new_mode:
		return
	edit_mode = new_mode
	clear_preview_block()
	clear_removal_hover()


func update_preview() -> void:
	if not is_instance_valid(vehicle):
		clear_preview_block()
		return
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		clear_preview_block()
		return
	var mouse := camera.get_global_mouse_position()
	preview_cell = vehicle.world_to_cell(mouse)
	if edit_mode == EditMode.DISMANTLE:
		clear_preview_block()
		update_vehicle_removal_hover()
		return
	clear_removal_hover()

	if selected_block == null:
		clear_preview_block()
		return
	if (
		preview_block == null
		or preview_block.block_id != selected_block.block_id
	):
		create_preview_block()

	preview_block.update_transform(vehicle, preview_cell, preview_rotation)
	vehicle.can_place_block(preview_block, preview_cell)


func create_preview_block() -> void:
	clear_preview_block()
	if selected_block == null or not is_instance_valid(vehicle):
		return
	var preview_scene := BlockDB.get_scene(selected_block.block_id)
	if preview_scene == null:
		return
	preview_block = preview_scene.instantiate() as Block
	if preview_block == null:
		return
	preview_block.block_id = selected_block.block_id
	vehicle.add_child(preview_block)
	preview_block.vehicle = vehicle
	preview_block.set_process(false)
	preview_block.set_physics_process(false)
	preview_block.set_process_input(false)
	preview_block.set_process_unhandled_input(false)
	disable_preview_features(preview_block)


func disable_preview_features(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionShape2D:
			child.disabled = true
		elif child is CollisionPolygon2D:
			child.disabled = true
		elif child is Area2D:
			child.monitoring = false
			child.monitorable = false
		disable_preview_features(child)


func clear_preview_block() -> void:
	if preview_block != null:
		preview_block.queue_free()
		preview_block = null
	preview_rotation = 0


func update_vehicle_removal_hover() -> void:
	if not is_instance_valid(vehicle):
		clear_removal_hover()
		return
	var cells: Array[Vector2i] = []
	var block := vehicle.get_block(preview_cell)
	if block != null:
		cells = block.get_occupied_cells()
	else:
		for record: Array in vehicle.blueprint_blocks:
			var record_cells := VehicleBlueprint.get_record_cells(record)
			if record_cells.has(preview_cell):
				cells = record_cells
				break
	if cells.is_empty():
		clear_removal_hover()
		return
	var overlay := ensure_removal_hover()
	overlay.attach_to(vehicle)
	var centers: Array[Vector2] = []
	for cell: Vector2i in cells:
		centers.append(
			(Vector2(cell) + Vector2(0.5, 0.5))
			* Globals.TILE_SIZE
		)
	overlay.show_centers(centers)


func ensure_removal_hover() -> RemovalHoverOverlay:
	if not is_instance_valid(removal_hover):
		removal_hover = RemovalHoverOverlay.new()
	return removal_hover


func clear_removal_hover() -> void:
	if is_instance_valid(removal_hover):
		removal_hover.clear()


func world_to_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos


func place_block() -> void:
	if not is_instance_valid(vehicle) or selected_block == null:
		return
	var block_id := selected_block.block_id
	var block_scene := BlockDB.get_scene(block_id)
	if block_scene == null:
		_show_status("Cannot build: block scene is missing")
		return
	if not _can_place_selected_block(block_scene):
		if (
			is_instance_valid(preview_block)
			and vehicle.can_place_block(preview_block, preview_cell)
			and is_instance_valid(active_workshop)
			and not active_workshop.is_vehicle_layout_inside(
				vehicle,
				preview_block
			)
		):
			_show_status("Outside maintenance bay area")
		else:
			_show_status("Cannot build here")
		return

	if not BlockDB.has_block(block_id):
		_show_status("Cannot build: block is not registered in BlockDB")
		return
	var cost := BlockDB.get_construction_cost(block_id)
	var build_position := vehicle.cell_to_world(preview_cell)
	var storages := _get_construction_storages(build_position)
	var payment := ConstructionSupport.consume(cost, storages)
	if not payment["ok"]:
		_show_status(
			"Missing: %s"
			% ConstructionSupport.format_cost(payment["missing"])
		)
		return

	if not vehicle.place_block(block_scene, preview_cell, preview_rotation):
		ConstructionSupport.refund(payment["withdrawals"])
		_show_status("Cannot build here; materials returned")
		return
	if not cost.is_empty():
		_show_status(
			"Built %s (-%s)"
			% [
				BlockDB.get_block_name(selected_block.block_id),
				ConstructionSupport.format_cost(cost),
			]
		)


func _can_place_selected_block(block_scene: PackedScene) -> bool:
	if is_instance_valid(preview_block):
		return (
			vehicle.can_place_block(preview_block, preview_cell)
			and _is_candidate_inside_workshop(preview_block)
		)
	var candidate := block_scene.instantiate() as Block
	if candidate == null:
		return false
	candidate.block_id = selected_block.block_id
	candidate.update_transform(vehicle, preview_cell, preview_rotation)
	var can_place := (
		vehicle.can_place_block(candidate, preview_cell)
		and _is_candidate_inside_workshop(candidate)
	)
	candidate.free()
	return can_place


func _is_candidate_inside_workshop(candidate: Block) -> bool:
	return (
		is_instance_valid(active_workshop)
		and is_instance_valid(vehicle)
		and active_workshop.is_vehicle_layout_inside(vehicle, candidate)
	)


func _get_construction_storages(
	build_world_position: Vector2
) -> Array[ItemStorage]:
	if active_workshop_building != null:
		return ConstructionSupport.get_workshop_candidate_storages(
			vehicle,
			active_workshop_building
		)
	return ConstructionSupport.get_candidate_storages(
		vehicle,
		build_world_position,
		construction_range_tiles * Globals.TILE_SIZE
	)


func remove_block() -> void:
	if not is_instance_valid(vehicle):
		return
	var block := vehicle.get_block(preview_cell)
	var blueprint_changed := vehicle.remove_blueprint_record_at_cell(
		preview_cell
	)
	if block != null:
		vehicle.destroy_block(block)
	elif blueprint_changed:
		_show_status("Removed block from blueprint")


func create_new_vehicle(
	world_pos: Vector2 = Vector2(INF, INF),
	replace_old: bool = false
) -> void:
	clear_preview_block()
	var previous_vehicle := vehicle
	var spawn_position := world_pos
	if not spawn_position.is_finite():
		if replace_old and is_instance_valid(previous_vehicle):
			spawn_position = previous_vehicle.global_position
		else:
			spawn_position = _get_new_vehicle_spawn_position(previous_vehicle)
	if replace_old and is_instance_valid(previous_vehicle):
		previous_vehicle.queue_free()
	var new_vehicle := vehicle_scene.instantiate() as Vehicle
	new_vehicle.vehicle_name = "New Vehicle %d" % new_vehicle_index
	if is_instance_valid(previous_vehicle):
		new_vehicle.owner_id = previous_vehicle.owner_id
	new_vehicle_index += 1
	if gamemap != null:
		gamemap.add_child(new_vehicle)
	else:
		get_tree().current_scene.add_child(new_vehicle)
	new_vehicle.global_position = spawn_position
	new_vehicle.rotation = 0.0
	set_selected_vehicle(new_vehicle)


func _get_new_vehicle_spawn_position(reference_vehicle: Vehicle) -> Vector2:
	if is_instance_valid(reference_vehicle):
		var rightmost_cell := 0
		for block: Block in reference_vehicle.blocks:
			for cell: Vector2i in block.get_occupied_cells():
				rightmost_cell = maxi(rightmost_cell, cell.x)
		var local_offset := Vector2(
			(rightmost_cell + 3) * Globals.TILE_SIZE,
			0.0
		)
		return reference_vehicle.to_global(local_offset)
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		return camera.get_screen_center_position()
	return Vector2.ZERO


func set_selected_vehicle(new_vehicle: Vehicle) -> void:
	clear_preview_block()
	clear_removal_hover()
	if is_instance_valid(vehicle):
		vehicle.set_blueprint_ghosts_visible(false)
	vehicle = new_vehicle if is_instance_valid(new_vehicle) else null
	if is_instance_valid(vehicle):
		vehicle.ensure_blueprint_from_blocks()
		vehicle.set_blueprint_ghosts_visible(is_editing_vehicle())
		_focus_camera_on_vehicle(vehicle)
	elif not is_editing_vehicle():
		interface_state = InterfaceState.CLOSED
	_apply_interface_state()


func _focus_camera_on_vehicle(target_vehicle: Vehicle) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera != null and camera.has_method("focus_on_vehicle"):
		camera.call("focus_on_vehicle", target_vehicle)


func _get_vehicle_under_mouse() -> Vehicle:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return null
	var query := PhysicsPointQueryParameters2D.new()
	query.position = camera.get_global_mouse_position()
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	for result: Dictionary in (
		get_viewport().world_2d.direct_space_state.intersect_point(query, 32)
	):
		var collider: Variant = result.get("collider")
		if collider is Vehicle:
			return collider as Vehicle
	return null


func _on_dismantle_button_pressed() -> void:
	toggle_mode()


func _on_finish_button_pressed() -> void:
	finish_workshop_edit()


func _on_auto_construct_button_pressed() -> void:
	auto_construct_missing_blocks()


func auto_construct_missing_blocks() -> void:
	if not is_instance_valid(vehicle):
		return
	var missing_records := vehicle.get_missing_blueprint_records()
	if missing_records.is_empty():
		_show_status("Blueprint is already complete")
		return

	var built_count := 0
	var material_failures := 0
	var blocked_count := 0
	for record: Array in missing_records:
		var result := _construct_blueprint_record(record)
		if result["ok"]:
			built_count += 1
		elif result["reason"] == "materials":
			material_failures += 1
		else:
			blocked_count += 1

	var remaining := vehicle.get_missing_blueprint_records().size()
	if remaining == 0:
		_show_status(
			"Auto construction complete: %d built" % built_count
		)
		return
	_show_status(
		"Auto built %d; %d remain (%d material, %d blocked)"
		% [
			built_count,
			remaining,
			material_failures,
			blocked_count,
		]
	)


func _construct_blueprint_record(record: Array) -> Dictionary:
	if VehicleBlueprint.get_matching_block(vehicle, record) != null:
		return {"ok": true}
	var block_id := int(record[0])
	var block_scene := BlockDB.get_scene(block_id)
	if block_scene == null:
		return {"ok": false, "reason": "blocked"}
	var cell := Vector2i(int(record[1]), int(record[2]))
	var rotation := int(record[3])
	var block_size := VehicleBlueprint._get_record_size(record)
	var candidate := block_scene.instantiate() as Block
	if candidate == null:
		return {"ok": false, "reason": "blocked"}
	candidate.block_id = block_id
	if (
		block_size != Vector2i.ZERO
		and candidate is ExpandableBlock
		and not (candidate as ExpandableBlock).configure_union_size(
			block_size
		)
	):
		candidate.free()
		return {"ok": false, "reason": "blocked"}
	candidate.update_transform(vehicle, cell, rotation)
	var can_place := (
		vehicle.can_place_block(candidate, cell)
		and _is_candidate_inside_workshop(candidate)
	)
	candidate.free()
	if not can_place:
		return {"ok": false, "reason": "blocked"}

	var cost := _get_record_construction_cost(record)
	var storages := _get_construction_storages(
		vehicle.cell_to_world(cell)
	)
	var payment := ConstructionSupport.consume(cost, storages)
	if not payment["ok"]:
		return {
			"ok": false,
			"reason": "materials",
			"missing": payment["missing"],
		}
	if not vehicle.place_block(
		block_scene,
		cell,
		rotation,
		block_size
	):
		ConstructionSupport.refund(payment["withdrawals"])
		return {"ok": false, "reason": "blocked"}
	var placed_block := vehicle.get_block(cell)
	if placed_block != null:
		VehicleBlueprint.apply_record_filter(record, placed_block)
	return {"ok": true}


func _get_record_construction_cost(record: Array) -> Dictionary:
	var cost := BlockDB.get_construction_cost(int(record[0]))
	var saved_size := VehicleBlueprint._get_record_size(record)
	var unit_count := 1
	if saved_size != Vector2i.ZERO:
		unit_count = maxi(1, saved_size.x * saved_size.y)
	for item_name: Variant in cost:
		cost[item_name] = int(cost[item_name]) * unit_count
	return cost


func _on_save_button_pressed() -> void:
	if not is_instance_valid(vehicle):
		return
	_open_blueprint_dialog(BlueprintDialogMode.SAVE)


func _on_load_button_pressed() -> void:
	if not is_instance_valid(vehicle):
		return
	_open_blueprint_dialog(BlueprintDialogMode.LOAD)


func _open_blueprint_dialog(mode: BlueprintDialogMode) -> void:
	var directory_result := VehicleBlueprint.ensure_directory()
	if not directory_result["ok"]:
		_show_status(directory_result["error"])
		return
	blueprint_dialog_mode = mode
	blueprint_dialog.access = FileDialog.ACCESS_USERDATA
	if mode == BlueprintDialogMode.SAVE:
		blueprint_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		blueprint_dialog.title = "Save Vehicle Blueprint"
		blueprint_dialog.ok_button_text = "Save"
		blueprint_dialog.current_dir = VehicleBlueprint.DIRECTORY
		blueprint_dialog.current_file = (
			vehicle.vehicle_name.validate_filename() + ".json"
		)
	else:
		blueprint_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		blueprint_dialog.title = "Load Vehicle Blueprint"
		blueprint_dialog.ok_button_text = "Load"
		blueprint_dialog.current_dir = VehicleBlueprint.DIRECTORY
		blueprint_dialog.current_file = ""
	blueprint_dialog.popup_centered_ratio(0.7)


func _on_blueprint_file_selected(path: String) -> void:
	var selected_mode := blueprint_dialog_mode
	blueprint_dialog_mode = BlueprintDialogMode.NONE
	if selected_mode == BlueprintDialogMode.SAVE:
		_save_blueprint_to_path(path)
	elif selected_mode == BlueprintDialogMode.LOAD:
		_load_blueprint_from_path(path)


func _save_blueprint_to_path(path: String) -> void:
	if not is_instance_valid(vehicle):
		_show_status("There is no vehicle to save.")
		return
	var result := VehicleBlueprint.save_path(
		vehicle,
		vehicle.vehicle_name,
		path
	)
	if result["ok"]:
		_show_status("Blueprint saved: %s" % result["name"])
	else:
		_show_status(result["error"])


func _load_blueprint_from_path(path: String) -> void:
	var result := VehicleBlueprint.load_path(path)
	if not result["ok"]:
		_show_status(result["error"])
		return

	var blueprint_data := result["data"].duplicate(true) as Dictionary
	var footprint_size := VehicleBlueprint.get_footprint_size(
		blueprint_data["blocks"]
	)
	var parent: Node = gamemap if gamemap != null else get_tree().current_scene
	var old_transform := Transform2D.IDENTITY
	var old_owner_id: StringName = &"player"
	if is_instance_valid(vehicle):
		old_transform = vehicle.global_transform
		old_owner_id = vehicle.owner_id
	if is_instance_valid(active_workshop):
		var session_rotation := (
			active_workshop.get_vehicle_front_rotation()
			if workshop_new_vehicle
			else vehicle.global_rotation
		)
		old_transform = active_workshop.get_aligned_vehicle_transform(
			footprint_size,
			session_rotation
		)

	var built := VehicleBlueprint.build(
		blueprint_data,
		parent,
		vehicle_scene,
		old_transform
	)
	if not built["ok"]:
		_show_status(built["error"])
		return

	clear_preview_block()
	var old_vehicle := vehicle
	var built_vehicle := built["vehicle"] as Vehicle
	built_vehicle.owner_id = old_owner_id
	if (
		is_instance_valid(active_workshop)
		and not _blueprint_records_fit_workshop(
			built_vehicle,
			blueprint_data["blocks"]
		)
	):
		built_vehicle.queue_free()
		_show_status("Blueprint does not fit inside this maintenance bay")
		return
	built_vehicle.freeze = active_workshop != null
	set_selected_vehicle(built_vehicle)
	workshop_context_vehicle = built_vehicle
	if is_instance_valid(active_workshop):
		active_workshop.untrack_candidate_vehicle(old_vehicle)
		active_workshop.track_candidate_vehicle(built_vehicle)
	if is_instance_valid(old_vehicle):
		old_vehicle.queue_free()
	refresh_workshop_camera()
	_show_status("Ghost blueprint loaded: %s" % built["name"])


func _blueprint_records_fit_workshop(
	target_vehicle: Vehicle,
	records: Array
) -> bool:
	if not is_instance_valid(active_workshop):
		return false
	for record: Array in records:
		var block_id := int(record[0])
		var block_scene := BlockDB.get_scene(block_id)
		if block_scene == null:
			return false
		var candidate := block_scene.instantiate() as Block
		if candidate == null:
			return false
		candidate.block_id = block_id
		var saved_size := VehicleBlueprint._get_record_size(record)
		if (
			saved_size != Vector2i.ZERO
			and candidate is ExpandableBlock
			and not (candidate as ExpandableBlock).configure_union_size(
				saved_size
			)
		):
			candidate.free()
			return false
		candidate.update_transform(
			target_vehicle,
			Vector2i(int(record[1]), int(record[2])),
			int(record[3])
		)
		var fits := active_workshop.is_vehicle_layout_inside(
			target_vehicle,
			candidate
		)
		candidate.free()
		if not fits:
			return false
	return true


func _on_blueprint_dialog_canceled() -> void:
	blueprint_dialog_mode = BlueprintDialogMode.NONE


func _on_com_visibility_changed(enabled: bool) -> void:
	com_icon.visible = (
		enabled and is_editing_vehicle() and is_instance_valid(vehicle)
	)


func _show_status(message: String) -> void:
	status_changed.emit(message)
