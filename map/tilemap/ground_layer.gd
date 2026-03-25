class_name GroundLayer
extends TileMapLayer

@onready var gamemap:GameMap = get_parent()
var ground_tiles:= {}


func _ready():
	build_ground_cache()


func build_ground_cache():
	var tileset = tile_set
	for source_id in tileset.get_source_count():
		var source = tileset.get_source(source_id)
		if source is TileSetAtlasSource:
			for id in source.get_tiles_count():
				var coords:Vector2i = source.get_tile_id(id)
				var data = source.get_tile_data(coords, 0)
				var matter = data.get_custom_data("matter")
				if matter != "":
					if TileDB.get_tile(matter)["layer"] == "ground":
						if not ground_tiles.has(matter):
							ground_tiles[matter] = []
						ground_tiles[matter].append({
							"source": source_id,
							"coords": coords
						})


func place_ground(pos:Vector2i, matter:String):
	var variants = ground_tiles[matter]
	var choice = variants[get_variant(pos,variants.size())]
	set_cell(pos, choice.source, choice.coords)


func get_variant(pos: Vector2i, variant_count:int) -> int:
	var rng := RandomNumberGenerator.new()
	# combine world seed + tile position
	rng.seed = hash(Vector3i(pos.x, pos.y, hash(gamemap.world_seed)))
	return rng.randi_range(0, variant_count - 1)

# SAVE AND LOAD

func save_chunk(chunk_x: int, chunk_y: int) -> PackedByteArray:
	const CHUNK_SIZE := 32
	var bytes := PackedByteArray()
	for ly in range(CHUNK_SIZE):
		for lx in range(CHUNK_SIZE):
			var x := chunk_x * CHUNK_SIZE + lx
			var y := chunk_y * CHUNK_SIZE + ly
			var cell := Vector2i(x, y)
			
			var celldata = get_cell_tile_data(cell)
			if not celldata:
				bytes.append(0)
			else:
				var cellmatter = celldata.get_custom_data("matter")
			# --- terrain (u8) ---
				bytes.append(TileDB.get_tile(cellmatter)["terrain_int"])   
	return bytes


func load_chunk(chunk_x:int, chunk_y:int, bytes:PackedByteArray, CHUNK_SIZE:int):
	var i := 0
	for ly in range(CHUNK_SIZE):
		for lx in range(CHUNK_SIZE):
			var terrain := bytes.decode_u8(i); i += 1
			if terrain == 0:
				continue
			var matter = TileDB.get_matter(terrain)
			var x := chunk_x * CHUNK_SIZE + lx
			var y := chunk_y * CHUNK_SIZE + ly
			var cell := Vector2i(x, y)
			place_ground(cell, matter)
