class_name VehicleEditor
extends Control

var vehicle : Vehicle
var selected_block : Block
var preview_cell : Vector2i
var preview_block: Block
var preview_rotation: int = 0
var design_mode : bool
var updating_name_field := false
var new_vehicle_index := 1
var edit_mode: EditMode = EditMode.BUILD
enum EditMode {
	BUILD,
	DISMANTLE
}
@onready var palette := $Panel/MarginContainer/Panel/Clipper/BlockPalette
@onready var COM_icon := $COMicon
@onready var vehicle_info_label := $Panel/RichTextLabel
@onready var vehicle_name_input: LineEdit = $Panel/LineEdit
@onready var blueprint_dialog: FileDialog = $BlueprintDialog
@export var saw_cursor: Texture2D
var vehicle_scene : PackedScene = load("res://vehicle/Vehicle.tscn")
@export var gamemap : GameMap


func _ready() -> void:
	vehicle_name_input.text_changed.connect(_on_vehicle_name_changed)
	set_selected_vehicle(null)


func _process(_delta):
	if vehicle != null and not is_instance_valid(vehicle):
		set_selected_vehicle(null)
	selected_block = palette.selected_block
	
	update_preview()
	
	if is_instance_valid(vehicle):
		COM_icon.position = world_to_screen(vehicle.to_global(vehicle.center_of_mass))


func _unhandled_input(event):
	# KEYBOARD
	if event.is_action_pressed("TOGGLE_EDITOR"):
		toggle_editor()
	if event.is_action_pressed("ROTATE"):
		preview_rotation = wrapi(preview_rotation + 1, 0, 4)
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_X:
			toggle_mode()
	if not visible:
		return
	
	# MOUSE
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var clicked_vehicle := _get_vehicle_under_mouse()
			if clicked_vehicle != null and clicked_vehicle != vehicle:
				set_selected_vehicle(clicked_vehicle)
				get_viewport().set_input_as_handled()
				return
			if not is_instance_valid(vehicle):
				return
		match edit_mode:
			
			EditMode.BUILD:
				if event.button_index == MOUSE_BUTTON_LEFT:
					place_block()
				elif event.button_index == MOUSE_BUTTON_RIGHT:
					palette.selected_block = null
			
			EditMode.DISMANTLE:
				if event.button_index == MOUSE_BUTTON_LEFT:
					remove_block()
				elif event.button_index == MOUSE_BUTTON_RIGHT:
					set_mode(EditMode.BUILD)


# UI functions

func toggle_editor():
	visible = !visible


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
	match edit_mode:
		
		EditMode.BUILD:
			Input.set_custom_mouse_cursor(null)
		
		EditMode.DISMANTLE:
			if saw_cursor != null:
				Input.set_custom_mouse_cursor(
					saw_cursor,
					Input.CURSOR_ARROW,
					Vector2(8, 8)
				)


func update_preview():
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
	
	if selected_block:
		if preview_block == null:
			create_preview_block()
		elif preview_block.block_name != selected_block.block_name:
			create_preview_block()
	
	preview_block.update_transform(vehicle, preview_cell, preview_rotation)
	var can_place := vehicle.can_place_block(preview_block, preview_cell)
	#set_preview_visual_state(can_place)


func create_preview_block() -> void:
	clear_preview_block()
	if selected_block == null:
		return
	var inst := selected_block.duplicate() as Block
	preview_block = inst
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


func world_to_screen(world_pos: Vector2):
	var canvas_transform = get_viewport().get_canvas_transform()
	return canvas_transform * world_pos


func update_vehicle_info():
	if not is_instance_valid(vehicle):
		vehicle_info_label.clear()
		return
	vehicle_info_label.clear()
	vehicle_info_label.append_text("weight: " + "%.1f" % (vehicle.total_mass / 1) + " T\n")
	vehicle_info_label.append_text("total power: " + str(vehicle.total_engine_power) + " kW") 


# Vehicle Building

func place_block():
	if not is_instance_valid(vehicle):
		return
	if selected_block == null:
		return
	
	var block_scene = load(selected_block.scene_file_path)
	vehicle.place_block(block_scene, preview_cell, preview_rotation)
	
	update_vehicle_info()


func remove_block():
	if not is_instance_valid(vehicle):
		return
	var block = vehicle.get_block(preview_cell)
	if block != null:
		vehicle.destroy_block(block)
	
	update_vehicle_info()


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
	updating_name_field = true
	if is_instance_valid(vehicle):
		vehicle_name_input.editable = true
		vehicle_name_input.remove_theme_color_override("font_color")
		vehicle_name_input.remove_theme_color_override("font_uneditable_color")
		vehicle_name_input.text = vehicle.vehicle_name
		COM_icon.visible = $Panel/CoM/TextureButton.button_pressed
	else:
		vehicle_name_input.editable = false
		var no_selection_color := Color(1.0, 0.2, 0.15)
		vehicle_name_input.add_theme_color_override("font_color", no_selection_color)
		vehicle_name_input.add_theme_color_override("font_uneditable_color", no_selection_color)
		vehicle_name_input.text = "No vehicle selected"
		COM_icon.hide()
	updating_name_field = false
	update_vehicle_info()


func _get_vehicle_under_mouse() -> Vehicle:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return null
	var query := PhysicsPointQueryParameters2D.new()
	query.position = camera.get_global_mouse_position()
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	for result: Dictionary in get_viewport().world_2d.direct_space_state.intersect_point(query, 32):
		var collider: Variant = result.get("collider")
		if collider is Vehicle:
			return collider as Vehicle
	return null


func _on_vehicle_name_changed(new_name: String) -> void:
	if updating_name_field or not is_instance_valid(vehicle):
		return
	vehicle.vehicle_name = new_name


# Signals

func _on_COM_button_pressed():
	COM_icon.visible = $Panel/CoM/TextureButton.button_pressed


func _on_dismantle_button_pressed():
	toggle_mode()


func _on_save_button_pressed() -> void:
	var result := VehicleBlueprint.save(vehicle, vehicle_name_input.text)
	if result["ok"]:
		_show_status("Blueprint saved: %s" % result["name"])
	else:
		_show_status(result["error"])


func _on_load_button_pressed() -> void:
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
	if is_instance_valid(vehicle):
		old_transform = vehicle.global_transform

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
	set_selected_vehicle(built["vehicle"])
	if is_instance_valid(old_vehicle):
		old_vehicle.queue_free()
	_show_status("Blueprint loaded: %s" % built["name"])


func _show_status(message: String) -> void:
	vehicle_info_label.text = message
