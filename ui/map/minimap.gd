extends FloatingPanel

@export var view_size_pixels := Vector2i(288, 288) # minimap window size
var center_cell := Vector2i.ZERO               # camera center
var zoom:int = 2
var max_zoom:int = 4
var min_zoom:int = 1
@onready var map:GameMap = $"../../Gamemap"
@onready var camera:Camera2D = $"../../Camera2D"
@onready var map_renderer = $Panel/MapRenderer

func _ready() -> void:
	map_renderer.map = map

func _process(_delta):
	#center_cell = map.ground.local_to_map(camera.position)
	map_renderer.scale = Vector2(zoom, zoom)
	map_renderer.position = -Vector2(center_cell - view_size_pixels/zoom/2) * zoom

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
	map_renderer.update_pixels(cells)

func _on_zoom_in_button_pressed() -> void:
	zoom = clampi(zoom * 2, min_zoom, max_zoom)


func _on_zoom_out_button_pressed() -> void:
	zoom = clampi(zoom / 2, min_zoom, max_zoom)
