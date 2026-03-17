class_name BlockPalette
extends Control

@export var editor : VehicleEditor

var blocks : Array = []
var selected_block : Block
var zoom:int = 2
var max_zoom:int = 4
var min_zoom:int = 1


func _ready():
	blocks = get_children()
	for block in blocks:
		create_button(block)


func create_button(block : Block):
	var button = BlockButton.new()
	button.block = block
	button.intiatialize()
	add_child(button)


func clamp_position():
	var rect = get_rect()
	position.x = clamp(position.x, -rect.size.x, size.x)
	position.y = clamp(position.y, -rect.size.y, size.y)


func _on_zoom_in_button_pressed():
	zoom = clampi(zoom + 1, min_zoom, max_zoom)
	scale = Vector2(zoom, zoom)


func _on_zoom_out_button_pressed():
	zoom = clampi(zoom - 1, min_zoom, max_zoom)
	scale = Vector2(zoom, zoom)
