class_name BlockButton
extends Control

const TILE_SIZE := 16

var block : Block


func intiatialize():
	size = block.size * TILE_SIZE
	position = block.position - (size / 2)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = block.block_name


func _gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var palette = get_parent() as BlockPalette
			palette.selected_block = block
