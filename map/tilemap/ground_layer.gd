class_name GroundLayer
extends TileMapLayer

@onready var gamemap: GameMap = get_parent()
var ground_tiles: Dictionary = {}


func _ready() -> void:
	build_ground_cache()


func build_ground_cache() -> void:
	ground_tiles.clear()
	for source_index in tile_set.get_source_count():
		var source_id := tile_set.get_source_id(source_index)
		var source := tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		for tile_index in source.get_tiles_count():
			var coordinates := source.get_tile_id(tile_index)
			var data := source.get_tile_data(coordinates, 0)
			if data == null:
				continue
			var block_id := int(data.get_custom_data("block_id"))
			if not BlockDB.is_ground(block_id):
				continue
			if not ground_tiles.has(block_id):
				ground_tiles[block_id] = []
			ground_tiles[block_id].append({
				"source": source_id,
				"coordinates": coordinates,
			})


func place_ground(position: Vector2i, block_id: int) -> bool:
	if not BlockDB.is_ground(block_id):
		return false
	if not ground_tiles.has(block_id):
		push_error(
			"No ground variants for block ID %d." % block_id
		)
		return false
	var variants: Array = ground_tiles[block_id]
	var choice: Dictionary = variants[
		get_variant(position, variants.size())
	]
	set_cell(
		position,
		int(choice["source"]),
		choice["coordinates"]
	)
	return true


func get_variant(position: Vector2i, variant_count: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(
		Vector3i(position.x, position.y, hash(gamemap.world_seed))
	)
	return rng.randi_range(0, variant_count - 1)


func get_ground_block_id_at(cell: Vector2i) -> int:
	var data := get_cell_tile_data(cell)
	if data == null:
		return BlockDB.INVALID_BLOCK_ID
	var block_id := int(data.get_custom_data("block_id"))
	return (
		block_id
		if BlockDB.is_ground(block_id)
		else BlockDB.INVALID_BLOCK_ID
	)


func save_chunk(chunk_x: int, chunk_y: int) -> PackedByteArray:
	const CHUNK_SIZE := 32
	var bytes := PackedByteArray()
	bytes.resize(CHUNK_SIZE * CHUNK_SIZE * 2)
	var index := 0
	for local_y in range(CHUNK_SIZE):
		for local_x in range(CHUNK_SIZE):
			var cell := Vector2i(
				chunk_x * CHUNK_SIZE + local_x,
				chunk_y * CHUNK_SIZE + local_y
			)
			var block_id := get_ground_block_id_at(cell)
			bytes.encode_u16(
				index,
				0 if block_id == BlockDB.INVALID_BLOCK_ID else block_id
			)
			index += 2
	return bytes


func load_chunk(
	chunk_x: int,
	chunk_y: int,
	bytes: PackedByteArray,
	chunk_size: int,
	format_version: int = 4
) -> void:
	var index := 0
	for local_y in range(chunk_size):
		for local_x in range(chunk_size):
			var block_id := 0
			if format_version >= 4:
				block_id = bytes.decode_u16(index)
				index += 2
			else:
				block_id = BlockDB.get_legacy_ground_block_id(
					bytes.decode_u8(index)
				)
				index += 1
			if block_id <= 0:
				continue
			if not BlockDB.is_ground(block_id):
				push_error("Unknown saved ground block ID %d." % block_id)
				continue
			var cell := Vector2i(
				chunk_x * chunk_size + local_x,
				chunk_y * chunk_size + local_y
			)
			place_ground(cell, block_id)
