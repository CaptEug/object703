class_name VehicleEditor
extends Control

var vehicle : Vehicle
var selected_block : Block
var preview_cell : Vector2i
var preview_block: Block
var preview_rotation: int = 0
var design_mode : bool
var edit_mode: EditMode = EditMode.BUILD
enum EditMode {
	BUILD,
	DISMANTLE
}
var overlay: Overlay = Overlay.NONE
enum Overlay {
	NONE,
	SHAFT,
	CONVEYOR,
	PIPE,
}

@onready var palette := $Panel/MarginContainer/Panel/Clipper/BlockPalette
@onready var COM_icon := $COMicon
@onready var vehicle_info_label := $Panel/RichTextLabel
@export var saw_cursor: Texture2D
var vehicle_scene : PackedScene = load("res://vehicle/Vehicle.tscn")
@export var gamemap : GameMap


func _ready():
	pass # Replace with function body.


func _process(_delta):
	selected_block = palette.selected_block
	
	if selected_block is Shaft:
		set_overlay(Overlay.SHAFT)
	else:
		set_overlay(Overlay.NONE)
		
	update_preview()
	
	if vehicle:
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
	
	# MOUSE
	if event is InputEventMouseButton and event.pressed:
		match overlay:
			
			Overlay.NONE:
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
			
			Overlay.SHAFT:
				match edit_mode:
					
					EditMode.BUILD:
						if event.button_index == MOUSE_BUTTON_LEFT:
							place_shaft()
						elif event.button_index == MOUSE_BUTTON_RIGHT:
							palette.selected_block = null
					
					EditMode.DISMANTLE:
						if event.button_index == MOUSE_BUTTON_LEFT:
							remove_shaft()
							vehicle.power_system.remove_shaft(preview_cell)
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


func set_overlay(new_overlay: Overlay) -> void:
	if overlay == new_overlay:
		return
	overlay = new_overlay
	update_vehicle_visuals()


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


func update_vehicle_visuals() -> void:
		vehicle.power_system.visible = overlay == Overlay.SHAFT


func update_preview():
	if vehicle == null:
		clear_preview_block()
		return
	
	var mouse := get_viewport().get_camera_2d().get_global_mouse_position()
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
	vehicle_info_label.clear()
	vehicle_info_label.append_text("weight: " + "%.1f" % (vehicle.total_mass / 1) + " T\n")
	vehicle_info_label.append_text("total power: " + str(vehicle.total_engine_power) + " kW") 


# Vehicle Building

func place_block():
	if vehicle == null:
		return
	if selected_block == null:
		return
	var block_scene = load(selected_block.scene_file_path)
	vehicle.place_block(block_scene, preview_cell, preview_rotation)
	
	update_vehicle_info()


func remove_block():
	if vehicle == null:
		return
	var block = vehicle.get_block(preview_cell)
	if block != null:
		vehicle.destroy_block(block)
	
	update_vehicle_info()


func place_shaft():
	if vehicle == null:
		return
	if selected_block == null:
		return
	vehicle.power_system.place_shaft(preview_cell)
	
	update_vehicle_info()


func remove_shaft():
	if vehicle == null:
		return
	vehicle.power_system.remove_shaft(preview_cell)
	
	update_vehicle_info()


func create_new_vehicle(world_pos: Vector2 = Vector2.ZERO, replace_old: bool = true) -> void:
	clear_preview_block()
	if replace_old and is_instance_valid(vehicle):
		vehicle.queue_free()
		vehicle = null
	var inst := vehicle_scene.instantiate()
	vehicle = inst as Vehicle
	if gamemap != null:
		gamemap.add_child(vehicle)
	else:
		get_tree().current_scene.add_child(vehicle)
	vehicle.global_position = world_pos
	vehicle.rotation = 0.0


# Signals

func _on_COM_button_pressed():
	COM_icon.visible = $Panel/CoM/TextureButton.button_pressed


func _on_dismantle_button_pressed():
	toggle_mode()
