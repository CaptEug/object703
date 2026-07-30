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
	map_renderer.update_cells(cells)


func _on_zoom_in_button_pressed() -> void:
	zoom = clampi(zoom + 1, min_zoom, max_zoom)


func _on_zoom_out_button_pressed() -> void:
	zoom = clampi(zoom - 1, min_zoom, max_zoom)


func _on_close_button_pressed():
	hide()
