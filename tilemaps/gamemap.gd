class_name GameMap
extends Node2D

@onready var ground:TileMapLayer = $GroundLayer
@onready var wall:WallLayer = $WallLayer
@onready var building:BuildingLayer = $BuildingLayer
var layers:Dictionary[String, TileMapLayer]
var world_name:String
var world_height:int = 256
var world_width:int = 256

@export var noise_height_text:NoiseTexture2D
var mapfolder_path:= "res://tilemaps/savedmaps/"



func _ready():
	world_name = "TestField"
	layers = {
		"wall": wall,
	}
	#generate_world(noise_height_text.noise)
	load_world("res://tilemaps/savedmaps/TestField.llh")
	
	
	# 加载蓝图并生成建筑
	building.load_all_blueprints()
	building.generate_buildings_from_layerdata(self)
	
	print("=== 游戏地图初始化完成 ===")

func _process(delta: float) -> void:
	if Input.is_mouse_button_pressed(MouseButton.MOUSE_BUTTON_LEFT):
		save_world()
		pass

func generate_world(noise:Noise):
	#terrain sets
	var height_dict = {
		"sandstone": [0, 0.5],
		"hematite": [0.2, 0.3],
		"crude_oil": [-INF, -0.5]
	}
	
	for x in range(world_width):
		for y in range(world_height):
			var noise_val = noise.get_noise_2d(x, y)
			for matter in height_dict:
				if noise_val > height_dict[matter][0] and noise_val <= height_dict[matter][1]:
					var terrain_int = TileDB.get_tile(matter)["terrain_int"]
					BetterTerrain.set_cell(wall, Vector2i(x, y), terrain_int)

	BetterTerrain.update_terrain_area(wall, Rect2i(Vector2i(0, 0), Vector2i(world_width, world_height)))
	wall.init_layerdata()

func save_world():
	const CHUNK_SIZE := 32
	assert(world_width % CHUNK_SIZE == 0)
	assert(world_height % CHUNK_SIZE == 0)
	var chunks_x := world_width / CHUNK_SIZE
	var chunks_y := world_height / CHUNK_SIZE
	
	var file = FileAccess.open(mapfolder_path + "%s.llh" % world_name, FileAccess.WRITE)
	 # ---- header ----
	file.store_buffer("WLD0".to_ascii_buffer()) # magic
	file.store_16(1)                           # version
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
	
	file.close()

func load_world(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to open world file")
		return
	
	# ---- header ----
	var magic := file.get_buffer(4).get_string_from_ascii()
	if magic != "WLD0":
		push_error("Invalid world file")
		return
	
	var version := file.get_16()
	world_width = file.get_16()
	world_height = file.get_16()
	var CHUNK_SIZE := file.get_8()
	
	var chunks_x := world_width / CHUNK_SIZE
	var chunks_y := world_height / CHUNK_SIZE
	
	# ---- layers ----
	var layer_count := file.get_16()
	
	for i in range(layer_count):
		var name_len := file.get_8()
		var layer_name := file.get_buffer(name_len).get_string_from_ascii()
		var chunk_count := file.get_32()
		var layer = layers[layer_name]
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
	
			layer.load_chunk(cx, cy, bytes, CHUNK_SIZE)
		
	file.close()



func serialize_layer(layer: TileMapLayer) -> Dictionary:
	var cells := []
	if layer is BuildingLayer:
		for cell in layer.layerdata:
			var celldata = layer.get_celldata(cell)
			cells.append({
				"croods": [cell.x, cell.y],
				"block_name": celldata["block_name"],
				"block_path": celldata["block_path"],
				"rotation": celldata["rotation"],
				"hp": celldata["hp"],
			})
	elif layer is WallLayer:
		for cell in layer.layerdata:
			var celldata = layer.get_celldata(cell)
			var tile_info = TileDB.get_tile(celldata["matter"])
			if tile_info["phase"] == "solid":
				cells.append({
					"croods": [cell.x, cell.y],
					"matter": celldata["matter"],
					"max_hp": celldata["max_hp"],
					"current_hp": celldata["current_hp"],
				})
			elif tile_info["phase"] == "liquid":
				cells.append({
					"croods": [cell.x, cell.y],
					"matter": celldata["matter"],
					"mass": celldata["mass"],
				})
	else: # GroundLayer
		for cell in layer.get_used_cells():
			var source_id = layer.get_cell_source_id(cell)
			var atlas_coords = layer.get_cell_atlas_coords(cell)
			cells.append({
				"croods": [cell.x, cell.y],
				"source_id": source_id,
				"atlas_croods": atlas_coords,
			})
	
	return {
		"cells": cells
	}
