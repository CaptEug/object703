class_name GameMap
extends Node2D

@onready var ground:TileMapLayer = $GroundLayer
@onready var wall:WallLayer = $WallLayer
@onready var building:BuildingLayer = $BuildingLayer
var world_height:int = 128
var world_width:int = 128

@export var noise_height_text:NoiseTexture2D

#terrain sets
var sandstone_int = 1
var sandstone_tiles_arr = []

func _ready():
	generate_world(noise_height_text.noise)
	wall.init_layerdata()
	
	# 加载蓝图并生成建筑
	building.load_all_blueprints()
	building.generate_buildings_from_layerdata(self)
	
	print("=== 游戏地图初始化完成 ===")


func _process(delta):
	if Input.is_mouse_button_pressed(MouseButton.MOUSE_BUTTON_LEFT):
		wall.add_liquid(wall.local_to_map(get_global_mouse_position()),"crude_oil", 5000*delta)
	elif Input.is_mouse_button_pressed(MouseButton.MOUSE_BUTTON_RIGHT):
		wall.remove_liquid(wall.local_to_map(get_global_mouse_position()), 5000*delta)

func generate_world(noise:Noise):
	for x in range(world_width):
		for y in range(world_height):
			var noise_val = noise.get_noise_2d(x, y)
			if noise_val > 0:
				sandstone_tiles_arr.append(Vector2i(x,y))
				
	BetterTerrain.set_cells(wall, sandstone_tiles_arr, sandstone_int)
	BetterTerrain.update_terrain_cells(wall, sandstone_tiles_arr, sandstone_int)


func generate_tile_blocks(layer:TileMapLayer):
	for cell in layer.get_used_cells():
		var tile_id = layer.get_cell_source_id(cell)
		if tile_id == -1:
			continue
		
		var tile_data = layer.get_cell_tile_data(cell)
		var scene_path = tile_data.get_custom_data("tile_scene")

		# load and instantiate the StaticBody scene
		var scene: PackedScene = load(scene_path)
		if scene == null:
			push_error("Invalid tile_scene: %s" % scene_path)
			continue

		var instance = scene.instantiate()

		# convert tile cell position to world position
		var world_pos = layer.map_to_local(cell)
		instance.position = world_pos
		instance.layer = layer
		instance.cell = cell
		instance.terrain_set = tile_data.terrain_set
		add_child(instance)
