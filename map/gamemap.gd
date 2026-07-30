class_name GameMap
extends Node2D

@onready var ground: GroundLayer = $GroundLayer
@onready var world_blocks:WorldBlockLayer = $WorldBlockLayer
@onready var liquid:LiquidLayer = $LiquidLayer
@onready var canvas_modulate:CanvasModulate = $CanvasModulate
@onready var vehicle_root: = $VehicleRoot

var wall: WorldBlockLayer:
	get:
		return world_blocks

@export var minimap : MiniMap
var layers:Dictionary[String, TileMapLayer]
var world_seed:String
var world_height:int = 256
var world_width:int = 256


func _ready():
	layers = {
		"ground": ground,
		"blocks": world_blocks,
		"liquid": liquid,
	}
	for validation_error: String in (
		BlockDB.validate_database(world_blocks.tile_set)
	):
		push_error(validation_error)
	
	print("=== 游戏地图初始化完成 ===")


func _process(_delta: float) -> void:
	pass


func generate_world():
	var noise := FastNoiseLite.new()
	noise.seed = int(world_seed)
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	#terrain sets
	var block_height_dict = {
		9: [0, 0.5],
		10: [0.2, 0.3],
	}
	var liquid_height_dict = {
		11: [-INF, -0.5],
	}
	
	world_blocks.begin_bulk_edit()
	liquid.begin_bulk_edit()
	for x in range(world_width):
		for y in range(world_height):
			#generate ground
			
			#generate wall
			var noise_val = noise.get_noise_2d(x, y)
			var generated_block_id := BlockDB.INVALID_BLOCK_ID
			for block_id: int in block_height_dict:
				if (
					noise_val > block_height_dict[block_id][0]
					and noise_val <= block_height_dict[block_id][1]
				):
					generated_block_id = block_id
			if generated_block_id != BlockDB.INVALID_BLOCK_ID:
				world_blocks.place_block(
					generated_block_id,
					Vector2i(x, y)
				)
			for block_id: int in liquid_height_dict:
				if (
					noise_val > liquid_height_dict[block_id][0]
					and noise_val <= liquid_height_dict[block_id][1]
				):
					liquid.set_liquid_cell(
						Vector2i(x, y),
						block_id,
						BlockDB.get_default_liquid_mass(block_id),
						false
					)
	world_blocks.end_bulk_edit()
	liquid.end_bulk_edit()
	
	# load map to minimap
	minimap.map_renderer.loadmap()
	minimap.map_renderer.queue_redraw()

func save_map(world_folder:String):
	const CHUNK_SIZE := 32
	assert(world_width % CHUNK_SIZE == 0)
	assert(world_height % CHUNK_SIZE == 0)
	var chunks_x := world_width / CHUNK_SIZE
	var chunks_y := world_height / CHUNK_SIZE
	
	var file = FileAccess.open(world_folder + "%s.map" % GameState.current_gamescene.world_name, FileAccess.WRITE)
	# ---- header ----
	file.store_buffer("MAP0".to_ascii_buffer()) # magic
	file.store_16(4)                           # version
	file.store_16(world_width)
	file.store_16(world_height)
	file.store_8(CHUNK_SIZE)
	
	file.store_16(layers.size())
	
	for layer_name in layers:
		var layer = layers[layer_name]
		
		# layer header
		file.store_8(layer_name.length())
		file.store_buffer(layer_name.to_ascii_buffer())
		file.store_32(chunks_x * chunks_y)
		
		for cy in range(chunks_y):
			for cx in range(chunks_x):
				var bytes = layer.save_chunk(cx, cy)
				file.store_16(cx)
				file.store_16(cy)
				file.store_32(bytes.size())
				file.store_buffer(bytes)

	var building_text := JSON.stringify(
		world_blocks.get_building_save_data()
	)
	var building_bytes := building_text.to_utf8_buffer()
	file.store_32(building_bytes.size())
	file.store_buffer(building_bytes)
	
	file.close()
	print("地图文件保存完成")

func load_map(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to open world file")
		return
	
	# ---- header ----
	var magic := file.get_buffer(4).get_string_from_ascii()
	if magic != "MAP0":
		push_error("Invalid world file")
		return
	
	var version := file.get_16()
	world_width = file.get_16()
	world_height = file.get_16()
	var CHUNK_SIZE := file.get_8()
	
	# ---- layers ----
	var layer_count := file.get_16()
	world_blocks.begin_bulk_edit()
	liquid.begin_bulk_edit()
	
	for i in range(layer_count):
		var name_len := file.get_8()
		var layer_name := file.get_buffer(name_len).get_string_from_ascii()
		var chunk_count := file.get_32()
		var layer = layers.get(layer_name)
		if version == 1 and layer_name == "wall":
			layer = world_blocks
		if layer == null:
			push_warning("Unknown layer: %s" % layer_name)
			for c in range(chunk_count):
				file.get_16() # cx
				file.get_16() # cy
				var size := file.get_32()
				file.seek(file.get_position() + size)
			continue
	
		for c in range(chunk_count):
			var cx := file.get_16()
			var cy := file.get_16()
			var data_size := file.get_32()
			var bytes := file.get_buffer(data_size)
	
			if version == 1 and layer_name == "wall":
				world_blocks.load_legacy_wall_chunk(
					cx,
					cy,
					bytes,
					CHUNK_SIZE,
					liquid
				)
			elif layer == liquid:
				liquid.load_chunk(
					cx,
					cy,
					bytes,
					CHUNK_SIZE,
					version
				)
			elif layer == ground:
				ground.load_chunk(
					cx,
					cy,
					bytes,
					CHUNK_SIZE,
					version
				)
			else:
				layer.load_chunk(cx, cy, bytes, CHUNK_SIZE)
		
	world_blocks.end_bulk_edit()
	liquid.end_bulk_edit()
	if version >= 2 and file.get_position() + 4 <= file.get_length():
		var metadata_size := file.get_32()
		if (
			metadata_size > 0
			and file.get_position() + metadata_size <= file.get_length()
		):
			var metadata_text := file.get_buffer(
				metadata_size
			).get_string_from_utf8()
			var metadata: Variant = JSON.parse_string(metadata_text)
			if metadata is Array:
				world_blocks.apply_building_save_data(metadata)
	file.close()
	
	# load map to minimap
	minimap.map_renderer.loadmap()
	minimap.map_renderer.queue_redraw()
