# BlockPreview.gd
extends Control

signal start_drag(control, offset)

var block_data: Block = null

func set_block_data(block: Block):
	block_data = block
	$TextureRect.texture = block.get_icon_texture()
	$Label.text = block.block_name

func _on_gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("start_drag", self, get_local_mouse_position())
