extends Node2D

var map: GameMap
var cell_colors: Dictionary[Vector2i, Color] = {}
var image: Image
var texture: ImageTexture
var size := Vector2i(256, 256)


func _ready() -> void:
	_create_image(size)


func _process(_delta: float) -> void:
	if map != null and is_visible_in_tree():
		queue_redraw()


func loadmap() -> void:
	if map == null:
		return
	var map_size := Vector2i(map.world_width, map.world_height)
	if image == null or image.get_size() != map_size:
		_create_image(map_size)
	else:
		image.fill(Color.TRANSPARENT)
	cell_colors.clear()
	for cell: Vector2i in map.ground.get_used_cells():
		_refresh_cell_color(cell)
	for cell: Vector2i in map.world_blocks.cell_occupancy:
		_refresh_cell_color(cell)
	for cell: Vector2i in map.liquid.layerdata:
		_refresh_cell_color(cell)
	for cell: Vector2i in cell_colors:
		if Rect2i(Vector2i.ZERO, image.get_size()).has_point(cell):
			image.set_pixelv(cell, cell_colors[cell])
	texture.update(image)
	queue_redraw()


func update_cells(cells: Array) -> void:
	for value: Variant in cells:
		var cell: Vector2i = value
		_refresh_cell_color(cell)
		var color: Color = cell_colors.get(cell, Color.TRANSPARENT)
		if Rect2i(Vector2i.ZERO, image.get_size()).has_point(cell):
			image.set_pixelv(cell, color)
	texture.update(image)
	queue_redraw()


func _refresh_cell_color(cell: Vector2i) -> void:
	var block_id := map.world_blocks.get_block_id_at(cell)
	if block_id != BlockDB.INVALID_BLOCK_ID:
		cell_colors[cell] = BlockDB.get_color(block_id)
		return
	var liquid_state := map.liquid.get_celldata(cell)
	if not liquid_state.is_empty():
		cell_colors[cell] = BlockDB.get_color(
			int(liquid_state["block_id"])
		)
		return
	var ground_block_id := map.ground.get_ground_block_id_at(cell)
	if ground_block_id != BlockDB.INVALID_BLOCK_ID:
		cell_colors[cell] = BlockDB.get_color(ground_block_id)
		return
	cell_colors.erase(cell)


func _draw() -> void:
	if texture != null:
		draw_texture(texture, Vector2.ZERO)
	_draw_vehicle_blocks()


func _draw_vehicle_blocks() -> void:
	if map == null or not is_instance_valid(map.ground):
		return
	var vehicle_colors := collect_vehicle_block_colors()
	for cell: Vector2i in vehicle_colors:
		draw_rect(
			Rect2(Vector2(cell), Vector2.ONE),
			vehicle_colors[cell]
		)


func collect_vehicle_block_colors() -> Dictionary[Vector2i, Color]:
	var result: Dictionary[Vector2i, Color] = {}
	if map == null or not is_instance_valid(map.ground):
		return result
	for node: Node in get_tree().get_nodes_in_group("vehicles"):
		var vehicle := node as Vehicle
		if not is_instance_valid(vehicle):
			continue
		for block: Block in vehicle.blocks:
			var block_color := BlockDB.get_color(block.block_id)
			for cell: Vector2i in block.get_occupied_cells():
				var world_position := vehicle.to_global(
					(Vector2(cell) + Vector2(0.5, 0.5))
					* Globals.TILE_SIZE
				)
				var map_cell := map.ground.local_to_map(
					map.ground.to_local(world_position)
				)
				result[map_cell] = block_color
	return result


func _create_image(image_size: Vector2i) -> void:
	size = Vector2i(maxi(image_size.x, 1), maxi(image_size.y, 1))
	image = Image.create(
		size.x,
		size.y,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(Color.TRANSPARENT)
	texture = ImageTexture.create_from_image(image)
