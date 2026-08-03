class_name GameMap
extends Node2D

const MAP_VERSION := 0
const MAP_CHUNK_SIZE := 32
const MAP_FILE_NAME := "terrain.map"
const GENERATION_GROUND_BLOCK := "Sandstone Ground"
const NATURAL_GENERATION_RULES := [
	{
		"block_name": "Hematite",
		"minimum": 0.2,
		"maximum": 0.3,
	},
	{
		"block_name": "Sandstone",
		"minimum": 0.0,
		"maximum": 0.5,
	},
]
const LIQUID_GENERATION_RULES := [
	{
		"block_name": "Crude Oil",
		"minimum": -INF,
		"maximum": -0.5,
	},
]

@onready var ground: GroundLayer = $GroundLayer
@onready var world_blocks:WorldBlockLayer = $WorldBlockLayer
@onready var liquid:LiquidLayer = $LiquidLayer
@onready var canvas_modulate:CanvasModulate = $CanvasModulate
@onready var vehicle_root: = $VehicleRoot

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


func generate_world() -> void:
	var ground_block_id := _resolve_generation_block_id(
		GENERATION_GROUND_BLOCK,
		&"ground"
	)
	var natural_rules := _resolve_generation_rules(
		NATURAL_GENERATION_RULES,
		&"natural"
	)
	var liquid_rules := _resolve_generation_rules(
		LIQUID_GENERATION_RULES,
		&"liquid"
	)
	if (
		ground_block_id == BlockDB.INVALID_BLOCK_ID
		or natural_rules.size() != NATURAL_GENERATION_RULES.size()
		or liquid_rules.size() != LIQUID_GENERATION_RULES.size()
	):
		push_error("World generation stopped because its block rules are invalid.")
		return
	if not ground.ground_tiles.has(ground_block_id):
		push_error(
			"World generation ground has no TileSet visual: %s."
			% GENERATION_GROUND_BLOCK
		)
		return

	var noise := FastNoiseLite.new()
	noise.seed = hash(world_seed)
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	world_blocks.begin_bulk_edit()
	liquid.begin_bulk_edit()
	for x in range(world_width):
		for y in range(world_height):
			var cell := Vector2i(x, y)
			ground.place_ground(cell, ground_block_id)
			var noise_value := noise.get_noise_2d(x, y)
			var natural_block_id := _select_generation_block(
				noise_value,
				natural_rules
			)
			if natural_block_id != BlockDB.INVALID_BLOCK_ID:
				world_blocks.place_block(natural_block_id, cell)
				continue
			var liquid_block_id := _select_generation_block(
				noise_value,
				liquid_rules
			)
			if liquid_block_id != BlockDB.INVALID_BLOCK_ID:
				liquid.set_liquid_cell(
					cell,
					liquid_block_id,
					BlockDB.get_default_liquid_mass(liquid_block_id),
					false
				)
	world_blocks.end_bulk_edit()
	liquid.end_bulk_edit()
	
	# load map to minimap
	if is_instance_valid(minimap):
		minimap.map_renderer.loadmap()
		minimap.map_renderer.queue_redraw()


func _resolve_generation_rules(
	definitions: Array,
	category: StringName
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition: Dictionary in definitions:
		var block_name := str(definition.get("block_name", ""))
		var block_id := _resolve_generation_block_id(
			block_name,
			category
		)
		var minimum := float(definition.get("minimum", 0.0))
		var maximum := float(definition.get("maximum", 0.0))
		if block_id == BlockDB.INVALID_BLOCK_ID:
			return []
		if minimum >= maximum:
			push_error(
				"Invalid generation range for %s: %s to %s."
				% [block_name, minimum, maximum]
			)
			return []
		result.append({
			"block_id": block_id,
			"minimum": minimum,
			"maximum": maximum,
		})
	return result


func _resolve_generation_block_id(
	block_name: String,
	category: StringName
) -> int:
	var block_id := BlockDB.get_id_for_name(block_name)
	var valid := false
	match category:
		&"ground":
			valid = BlockDB.is_ground(block_id)
		&"natural":
			valid = (
				BlockDB.is_natural(block_id)
				and BlockDB.can_place_on(block_id, BlockDB.HOST_WORLD)
			)
		&"liquid":
			valid = BlockDB.is_liquid(block_id)
	if valid:
		return block_id
	push_error(
		"Generation block %s is missing or is not %s."
		% [block_name, category]
	)
	return BlockDB.INVALID_BLOCK_ID


func _select_generation_block(
	noise_value: float,
	rules: Array[Dictionary]
) -> int:
	for rule: Dictionary in rules:
		if (
			noise_value > float(rule["minimum"])
			and noise_value <= float(rule["maximum"])
		):
			return int(rule["block_id"])
	return BlockDB.INVALID_BLOCK_ID

func save_map(world_folder: String) -> bool:
	assert(world_width % MAP_CHUNK_SIZE == 0)
	assert(world_height % MAP_CHUNK_SIZE == 0)
	var chunks_x := world_width / MAP_CHUNK_SIZE
	var chunks_y := world_height / MAP_CHUNK_SIZE
	
	var file = FileAccess.open(
		world_folder + MAP_FILE_NAME,
		FileAccess.WRITE
	)
	if file == null:
		push_error("Failed to open world map for saving")
		return false
	# ---- header ----
	file.store_buffer("MAP0".to_ascii_buffer()) # magic
	file.store_16(MAP_VERSION)
	file.store_16(world_width)
	file.store_16(world_height)
	file.store_8(MAP_CHUNK_SIZE)
	
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

	file.close()
	print("Terrain save complete")
	return true

func load_map(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to open world file")
		return false
	
	# ---- header ----
	var magic := file.get_buffer(4).get_string_from_ascii()
	if magic != "MAP0":
		push_error("Invalid world file")
		file.close()
		return false
	
	var version := file.get_16()
	if version != MAP_VERSION:
		push_error(
			"Unsupported world file version %d; expected version %d"
			% [version, MAP_VERSION]
		)
		file.close()
		return false
	world_width = file.get_16()
	world_height = file.get_16()
	var chunk_size := file.get_8()
	
	# ---- layers ----
	var layer_count := file.get_16()
	world_blocks.begin_bulk_edit()
	liquid.begin_bulk_edit()
	
	for i in range(layer_count):
		var name_len := file.get_8()
		var layer_name := file.get_buffer(name_len).get_string_from_ascii()
		var chunk_count := file.get_32()
		var layer = layers.get(layer_name)
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
	
			layer.load_chunk(cx, cy, bytes, chunk_size)

	world_blocks.end_bulk_edit()
	liquid.end_bulk_edit()
	file.close()
	
	# load map to minimap
	if is_instance_valid(minimap):
		minimap.map_renderer.loadmap()
		minimap.map_renderer.queue_redraw()
	return true
