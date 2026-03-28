class_name MiniMap
extends FloatingPanel

var center_cell := Vector2i.ZERO               # camera center
var zoom:int = 2
var max_zoom:int = 4
var min_zoom:int = 1
@export var map:GameMap
@export var camera:Camera2D
@onready var map_renderer = $MarginContainer/Screen/Clipper/MapRenderer
@onready var view_screen = $MarginContainer/Screen


func _ready() -> void:
	map_renderer.map = map


func _process(_delta):
	var screen_size = view_screen.size
	center_cell = map.ground.local_to_map(camera.position)
	map_renderer.scale = Vector2(zoom, zoom)
	map_renderer.position = - Vector2(center_cell * zoom) + (screen_size/2)


func update_cellmap(cells:Array):
	for cell in cells:
		if map.building.layerdata.has(cell):
			map_renderer.cell_map[cell] = "building"
			continue
		var walldata = map.wall.get_cell_tile_data(cell)
		if walldata:
			map_renderer.cell_map[cell] = walldata.get_custom_data("matter")
			continue
		var grounddata = map.ground.get_cell_tile_data(cell)
		if grounddata:
			map_renderer.cell_map[cell] = grounddata.get_custom_data("matter")
			continue
		map_renderer.cell_map.erase(cell)
	map_renderer.update_pixels(cells)


func _on_zoom_in_button_pressed() -> void:
	zoom = clampi(zoom + 1, min_zoom, max_zoom)


func _on_zoom_out_button_pressed() -> void:
	zoom = clampi(zoom - 1, min_zoom, max_zoom)


func _on_close_button_pressed():
	hide()
