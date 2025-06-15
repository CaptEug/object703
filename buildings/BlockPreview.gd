extends Control
class_name BlockPreview

signal start_drag(control: Control, offset: Vector2)

@export var block_scene: PackedScene
@onready var texture_rect: TextureRect = $TextureRect
@onready var label: Label = $Label

func setup(scene: PackedScene):
	block_scene = scene
	var temp = scene.instantiate()
	
	if temp.has_method("get_icon_texture"):
		texture_rect.texture = temp.get_icon_texture()
	label.text = temp.block_name if temp.has("block_name") else "Unnamed"
	temp.queue_free()

func _on_gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		start_drag.emit(self, get_local_mouse_position())
