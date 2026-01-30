extends Node2D

var map:GameMap
var cell_map:Dictionary[Vector2i, String] = {}
var image: Image
var texture: ImageTexture
var size := Vector2i(256, 256)

func _ready():
	image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	texture = ImageTexture.create_from_image(image)

func loadmap():
	if !map:
		return
	for cell in map.ground.get_used_cells():
		cell_map[cell] = map.ground.get_cell_tile_data(cell).get_custom_data("matter")
	for cell in map.wall.get_used_cells():
		cell_map[cell] = map.wall.get_cell_tile_data(cell).get_custom_data("matter")
	for cell in map.building.layerdata:
		cell_map[cell] = "building"
	
	for cell in cell_map:
		var color = TileDB.get_tile(cell_map[cell])["color"]
		draw_pixel(cell, color)


func draw_pixel(pos: Vector2i, color: Color):
	image.set_pixelv(pos, color)
	texture.update(image)

func update_pixels(cells:Array):
	for cell in cells:
		var color = TileDB.get_tile(cell_map[cell])["color"]
		image.set_pixelv(cell, color)
	texture.update(image)
	queue_redraw()

func _draw():
	draw_texture(texture, Vector2.ZERO)
