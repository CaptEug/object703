class_name VehicleEditor
extends Control

var vehicle : Vehicle
var selected_block : Block
var preview_cell : Vector2i
var preview_block: Block
var preview_rotation: int = 0
var design_mode : bool

@onready var palette := $Panel/MarginContainer/Panel/Clipper/BlockPalette
@onready var COM_icon := $COMicon
var vehicle_scene : PackedScene = load("res://vehicles/Vehicle.tscn")
@export var gamemap : GameMap


func _ready():
	pass # Replace with function body.


func _process(_delta):
	selected_block = palette.selected_block
	update_preview()
	if vehicle:
		COM_icon.position = world_to_screen(vehicle.to_global(vehicle.com))


func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			place_block()
		if event.button_index == MOUSE_BUTTON_RIGHT:
			remove_block()


# UI functions

func update_preview():
	if selected_block == null or vehicle == null:
		clear_preview_block()
		return
	
	if selected_block:
		if preview_block == null:
			create_preview_block()
		elif preview_block.block_name != selected_block.block_name:
			create_preview_block()
	
	if preview_block == null:
		return
	
	var mouse := get_viewport().get_camera_2d().get_global_mouse_position()
	preview_cell = vehicle.world_to_cell(mouse)
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
	preview_cell = Vector2i.ZERO
	preview_rotation = 0


func world_to_screen(world_pos: Vector2):
	var canvas_transform = get_viewport().get_canvas_transform()
	return canvas_transform * world_pos


# Vehicle Building

func place_block():
	if vehicle == null:
		return
	if selected_block == null:
		return
	vehicle.place_block(selected_block, preview_cell, preview_rotation)


func remove_block():
	var block = vehicle.get_block(preview_cell)
	if block != null:
		vehicle.destroy_block(block)


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
