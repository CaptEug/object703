class_name Factory
extends Area2D

@export var build_area_size := Vector2(800, 600)
@export var max_vehicle_size := Vector2(20, 10)  # 最大尺寸(格子数)
@export var available_blocks: Array[PackedScene] = [
	preload("res://blocks/armor.tscn"),
	preload("res://blocks/bridge.tscn")
]

var is_building := false
var build_ui: Node = null

func _ready():
	connect("input_event", _on_input_event)

func _on_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		enter_build_mode()

func enter_build_mode():
	if is_building: return
	
	is_building = true
	build_ui = preload("res://buildings/BuildUI.tscn").instantiate()
	build_ui.factory = self
	get_tree().root.add_child(build_ui)

func exit_build_mode():
	if build_ui:
		build_ui.queue_free()
	is_building = false
	build_ui = null
