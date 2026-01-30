extends FloatingPanel

@export var view_size_pixels := Vector2i(288, 288) # minimap window size
var center_cell := Vector2i.ZERO               # camera center
@export var pixel_size := 2
var map:GameMap
var camera:Camera2D
var max_zoom:int = 4
var min_zoom:int = 1

func _ready() -> void:
	# Get current game map
	for child in get_tree().current_scene.get_children():
		if child is GameMap:
			map = child
			break
	# Get camera
	camera = get_tree().current_scene.find_child("Camera2D") as Camera2D

func _process(_delta):
	center_cell = map.ground.local_to_map(camera.position)
	queue_redraw()

func _draw():
	var offset = Vector2(16, 14)
	var half := view_size_pixels / (pixel_size * 2)
	# cache highest tile per cell
	var cell_map:Dictionary[Vector2i, String] = {}
	
	#for cell in map.ground.get_used_cells():
		#cell_map[cell] = map.ground.get_cell_tile_data(cell).get_custom_data("matter")
		
	for cell in map.wall.get_used_cells():
		if abs(cell.x - center_cell.x) > half.x or abs(cell.y - center_cell.y) > half.y:
			continue
		cell_map[cell] = map.wall.get_cell_tile_data(cell).get_custom_data("matter")
	
	for cell in map.building.layerdata:
		if abs(cell.x - center_cell.x) > half.x or abs(cell.y - center_cell.y) > half.y:
			continue
		cell_map[cell] = "building"
	
	for cell in cell_map:
		var color = TileDB.get_tile(cell_map[cell])["color"]
		if color == null:
			color = Color.DIM_GRAY
		draw_rect(
			Rect2(
				offset + world_cell_to_minimap(cell) * pixel_size,
				Vector2(pixel_size, pixel_size)
			),
			color
		)

func world_cell_to_minimap(cell: Vector2i) -> Vector2:
	var half := view_size_pixels / (2 * pixel_size)
	var local := cell - center_cell + half
	return local

func set_zoom(zoom: float):
	zoom = clampi(zoom, min_zoom, max_zoom)
	pixel_size = zoom
	queue_redraw()


func _on_zoom_in_button_pressed() -> void:
	set_zoom(2 * pixel_size)


func _on_zoom_out_button_pressed() -> void:
	set_zoom(pixel_size / 2)
