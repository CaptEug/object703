class_name VehicleEditor
extends Control

enum InterfaceState {
	CLOSED,
	INSPECT,
	EDIT,
}

enum EditMode {
	BUILD,
	DISMANTLE,
}

const INSPECT_PANEL_WIDTH := 256.0

var vehicle: Vehicle
var selected_block: Block
var preview_cell: Vector2i
var preview_block: Block
var preview_rotation := 0
var interface_state := InterfaceState.CLOSED
var edit_mode := EditMode.BUILD
var new_vehicle_index := 1
var selection_click_active := false

@onready var editor_dock: Panel = $EditorDock
@onready var vehicle_panel: VehiclePanel = $EditorDock/VehiclePanel
@onready var editor_tools: VBoxContainer = $EditorDock/EditorTools
@onready var palette_area: MarginContainer = $EditorDock/PaletteArea
@onready var palette: BlockPalette = (
	$EditorDock/PaletteArea/Panel/Clipper/BlockPalette
)
@onready var com_icon: Sprite2D = $COMicon
@onready var com_button: TextureButton = $EditorDock/EditorTools/CoMButton
@onready var blueprint_dialog: FileDialog = $BlueprintDialog

@export var saw_cursor: Texture2D
@export var gamemap: GameMap

var vehicle_scene: PackedScene = load("res://vehicle/Vehicle.tscn")

@export_range(1.0, 64.0, 1.0) var construction_range_tiles := 8.0


func _ready() -> void:
	vehicle_panel.edit_requested.connect(enter_edit_mode)
	vehicle_panel.finish_requested.connect(exit_edit_mode)
	vehicle_panel.close_requested.connect(close_vehicle_panel)
	set_selected_vehicle(null)
	_apply_interface_state()


func _process(_delta: float) -> void:
	if (
		selection_click_active
		and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	):
		selection_click_active = false
	if vehicle != null and not is_instance_valid(vehicle):
		set_selected_vehicle(null)
	selected_block = palette.selected_block
	if is_editing_vehicle():
		update_preview()
	else:
		clear_preview_block()
	if (
		is_editing_vehicle()
		and is_instance_valid(vehicle)
		and com_button.button_pressed
	):
		com_icon.position = world_to_screen(
			vehicle.to_global(vehicle.center_of_mass)
		)


func _unhandled_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
	):
		selection_click_active = false

	if event.is_action_pressed("TOGGLE_EDITOR"):
		if is_editing_vehicle():
			exit_edit_mode()
		elif is_instance_valid(vehicle):
			enter_edit_mode()
		get_viewport().set_input_as_handled()
		return

	if is_editing_vehicle():
		_handle_editor_input(event)
	else:
		_handle_inspection_input(event)


func _handle_inspection_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var clicked_vehicle := _get_vehicle_under_mouse()
	if clicked_vehicle == null:
		return
	selection_click_active = true
	inspect_vehicle(clicked_vehicle)
	get_viewport().set_input_as_handled()


func _handle_editor_input(event: InputEvent) -> void:
	if event.is_action_pressed("ROTATE"):
		preview_rotation = wrapi(preview_rotation + 1, 0, 4)
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


func inspect_vehicle(clicked_vehicle: Vehicle) -> void:
	if not is_instance_valid(clicked_vehicle):
		return
	if is_editing_vehicle() and clicked_vehicle != vehicle:
		return
	set_selected_vehicle(clicked_vehicle)
	if not is_editing_vehicle():
		interface_state = InterfaceState.INSPECT
		_apply_interface_state()


func enter_edit_mode() -> void:
	if not is_instance_valid(vehicle):
		return
	interface_state = InterfaceState.EDIT
	vehicle_panel.set_editing(true)
	_apply_interface_state()
	update_cursor()


func exit_edit_mode() -> void:
	clear_preview_block()
	Input.set_custom_mouse_cursor(null)
	interface_state = (
		InterfaceState.INSPECT
		if is_instance_valid(vehicle)
		else InterfaceState.CLOSED
	)
	vehicle_panel.set_editing(false)
	_apply_interface_state()


func close_vehicle_panel() -> void:
	clear_preview_block()
	Input.set_custom_mouse_cursor(null)
	palette.selected_block = null
	interface_state = InterfaceState.CLOSED
	set_selected_vehicle(null)
	_apply_interface_state()


func toggle_editor() -> void:
	if is_editing_vehicle():
		exit_edit_mode()
	elif is_instance_valid(vehicle):
		enter_edit_mode()


func is_editing_vehicle() -> bool:
	return interface_state == InterfaceState.EDIT


func is_fire_suppressed() -> bool:
	return selection_click_active or is_editing_vehicle()


func _apply_interface_state() -> void:
	var is_open := interface_state != InterfaceState.CLOSED
	editor_dock.visible = is_open
	editor_tools.visible = is_editing_vehicle()
	palette_area.visible = is_editing_vehicle()
	vehicle_panel.set_editing(is_editing_vehicle())
	if is_editing_vehicle():
		editor_dock.anchor_right = 1.0
		editor_dock.offset_right = 0.0
	else:
		editor_dock.anchor_right = 0.0
		editor_dock.offset_right = INSPECT_PANEL_WIDTH
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
	update_cursor()


func update_cursor() -> void:
	if not is_editing_vehicle():
		Input.set_custom_mouse_cursor(null)
		return
	if edit_mode == EditMode.BUILD:
		Input.set_custom_mouse_cursor(null)
	elif saw_cursor != null:
		Input.set_custom_mouse_cursor(
			saw_cursor,
			Input.CURSOR_ARROW,
			Vector2(8, 8)
		)


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

	if selected_block == null or edit_mode != EditMode.BUILD:
		clear_preview_block()
		return
	if (
		preview_block == null
		or preview_block.block_name != selected_block.block_name
	):
		create_preview_block()

	preview_block.update_transform(vehicle, preview_cell, preview_rotation)
	vehicle.can_place_block(preview_block, preview_cell)


func create_preview_block() -> void:
	clear_preview_block()
	if selected_block == null or not is_instance_valid(vehicle):
		return
	preview_block = selected_block.duplicate() as Block
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


func world_to_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos


func place_block() -> void:
	if not is_instance_valid(vehicle) or selected_block == null:
		return
	var block_scene := load(selected_block.scene_file_path) as PackedScene
	if block_scene == null:
		_show_status("Cannot build: block scene is missing")
		return
	if not _can_place_selected_block(block_scene):
		_show_status("Cannot build here")
		return

	var block_id := BlockDB.get_id_for_scene(selected_block.scene_file_path)
	if block_id < 0:
		_show_status("Cannot build: block is not registered in BlockDB")
		return
	var cost := BlockDB.get_construction_cost(block_id)
	var build_position := vehicle.cell_to_world(preview_cell)
	var storages := ConstructionMaterials.get_candidate_storages(
		vehicle,
		build_position,
		construction_range_tiles * Globals.TILE_SIZE
	)
	var payment := ConstructionMaterials.consume(cost, storages)
	if not payment["ok"]:
		_show_status(
			"Missing: %s"
			% ConstructionMaterials.format_cost(payment["missing"])
		)
		return

	if not vehicle.place_block(block_scene, preview_cell, preview_rotation):
		ConstructionMaterials.refund(payment["withdrawals"])
		_show_status("Cannot build here; materials returned")
		return
	if not cost.is_empty():
		_show_status(
			"Built %s (-%s)"
			% [
				selected_block.block_name,
				ConstructionMaterials.format_cost(cost),
			]
		)
	vehicle_panel.refresh_information()


func _can_place_selected_block(block_scene: PackedScene) -> bool:
	if is_instance_valid(preview_block):
		return vehicle.can_place_block(preview_block, preview_cell)
	var candidate := block_scene.instantiate() as Block
	if candidate == null:
		return false
	candidate.update_transform(vehicle, preview_cell, preview_rotation)
	var can_place := vehicle.can_place_block(candidate, preview_cell)
	candidate.free()
	return can_place


func remove_block() -> void:
	if not is_instance_valid(vehicle):
		return
	var block := vehicle.get_block(preview_cell)
	if block != null:
		vehicle.destroy_block(block)
	vehicle_panel.refresh_information()


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
	vehicle = new_vehicle if is_instance_valid(new_vehicle) else null
	vehicle_panel.set_vehicle(vehicle)
	if is_instance_valid(vehicle):
		_focus_camera_on_vehicle(vehicle)
		if interface_state == InterfaceState.CLOSED:
			interface_state = InterfaceState.INSPECT
	else:
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


func _on_save_button_pressed() -> void:
	if not is_instance_valid(vehicle):
		return
	var result := VehicleBlueprint.save(vehicle, vehicle.vehicle_name)
	if result["ok"]:
		_show_status("Blueprint saved: %s" % result["name"])
	else:
		_show_status(result["error"])


func _on_load_button_pressed() -> void:
	if not is_instance_valid(vehicle):
		return
	var directory_result := VehicleBlueprint.ensure_directory()
	if not directory_result["ok"]:
		_show_status(directory_result["error"])
		return
	blueprint_dialog.access = FileDialog.ACCESS_USERDATA
	blueprint_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	blueprint_dialog.current_dir = VehicleBlueprint.DIRECTORY
	blueprint_dialog.popup_centered_ratio(0.7)


func _on_blueprint_file_selected(path: String) -> void:
	var result := VehicleBlueprint.load_path(path)
	if not result["ok"]:
		_show_status(result["error"])
		return

	var parent: Node = gamemap if gamemap != null else get_tree().current_scene
	var old_transform := Transform2D.IDENTITY
	var old_owner_id: StringName = &"player"
	if is_instance_valid(vehicle):
		old_transform = vehicle.global_transform
		old_owner_id = vehicle.owner_id

	var built := VehicleBlueprint.build(
		result["data"],
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
	set_selected_vehicle(built_vehicle)
	if is_instance_valid(old_vehicle):
		old_vehicle.queue_free()
	_show_status("Blueprint loaded: %s" % built["name"])


func _on_com_visibility_changed(enabled: bool) -> void:
	com_icon.visible = (
		enabled and is_editing_vehicle() and is_instance_valid(vehicle)
	)


func _show_status(message: String) -> void:
	vehicle_panel.show_status(message)
