class_name GameMap
extends Node2D

@onready var ground:TileMapLayer = $GroundLayer
@onready var wall:WallLayer = $WallLayer
@onready var building:BuildingLayer = $BuildingLayer
var world_name:String
var world_height:int = 128
var world_width:int = 128

@export var noise_height_text:NoiseTexture2D
var mapfolder_path:= "res://tilemaps/savedmaps/"

#terrain sets
var sandstone_int = 1
var sandstone_tiles_arr = []

func _ready():
	world_name = "TestField"
	generate_world(noise_height_text.noise)
	wall.init_layerdata()
	
	# 加载蓝图并生成建筑
	building.load_all_blueprints()
	building.generate_buildings_from_layerdata(self)
	
	print("=== 游戏地图初始化完成 ===")

func _process(delta: float) -> void:
	if Input.is_mouse_button_pressed(MouseButton.MOUSE_BUTTON_LEFT):
		save_world()

func generate_world(noise:Noise):
	for x in range(world_width):
		for y in range(world_height):
			var noise_val = noise.get_noise_2d(x, y)
			if noise_val > 0:
				sandstone_tiles_arr.append(Vector2i(x,y))
				
	BetterTerrain.set_cells(wall, sandstone_tiles_arr, sandstone_int)
	BetterTerrain.update_terrain_cells(wall, sandstone_tiles_arr, sandstone_int)


func save_world():
	var layers = {"ground": ground, "wall": wall, "building": building}
	var tilemaps := {}
	
	for layer in layers:
		tilemaps[layer] = serialize_layer(layers[layer])
	
	var world := {
		"tilemaps": tilemaps,
		#"vehicles":
		#"metadata":
	}

	var file = FileAccess.open(mapfolder_path + "%s.json" % world_name, FileAccess.WRITE)
	file.store_string(JSON.stringify(world,"\t"))
	file.close()

func load_world(file):
	pass

func serialize_layer(layer: TileMapLayer) -> Dictionary:
	var cells := []
	if layer is BuildingLayer:
		for cell in layer.layerdata:
			var celldata = layer.get_celldata(cell)
			cells.append({
				"croods": [cell],
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
					"croods": [cell],
					"matter": celldata["matter"],
					"max_hp": celldata["max_hp"],
					"current_hp": celldata["current_hp"],
				})
			elif tile_info["phase"] == "liquid":
				cells.append({
					"croods": [cell],
					"matter": celldata["matter"],
					"mass": celldata["matter"],
				})
	else: # GroundLayer
		for pos in layer.get_used_cells():
			var source_id = layer.get_cell_source_id(pos)
			var atlas_coords = layer.get_cell_atlas_coords(pos)
			cells.append({
				"croods": pos,
				"source_id": source_id,
				"atlas_croods": atlas_coords,
			})
	
	return {
		"cells": cells
	}
