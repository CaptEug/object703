extends Node

var ground:TileMapLayer
var wall:TileMapLayer



func _ready():
	ground = find_child("Grond") as TileMapLayer
	wall = find_child("Wall") as TileMapLayer
	generate_tile_blocks(wall)


func _process(delta):
	pass


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
