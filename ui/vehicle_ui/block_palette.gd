class_name BlockPalette
extends Control

@export_enum("vehicle", "world") var host_name := BlockDB.HOST_VEHICLE
@export var constructed_only := true

var blocks: Array[Block] = []
var selected_block : Block
var zoom:int = 2
var max_zoom:int = 4
var min_zoom:int = 1


func _ready():
	for child: Node in get_children():
		var block := child as Block
		if block == null:
			continue
		if not _is_available(block):
			block.hide()
			block.process_mode = Node.PROCESS_MODE_DISABLED
			continue
		blocks.append(block)
		create_button(block)
	scale = Vector2(zoom, zoom)


func _is_available(block: Block) -> bool:
	return (
		BlockDB.can_place_on(block.block_id, host_name)
		and (
			not constructed_only
			or BlockDB.is_constructed(block.block_id)
		)
	)


func create_button(block : Block):
	var button = BlockButton.new()
	button.block = block
	button.intiatialize()
	add_child(button)


func _on_zoom_in_button_pressed():
	zoom = clampi(zoom + 1, min_zoom, max_zoom)
	scale = Vector2(zoom, zoom)


func _on_zoom_out_button_pressed():
	zoom = clampi(zoom - 1, min_zoom, max_zoom)
	scale = Vector2(zoom, zoom)
