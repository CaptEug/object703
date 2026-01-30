extends Node

var tiles = {
	# Solid Tile
	"sandstone":{
		"layer": "wall",
		"phase": "solid",
		"hp": 400,
		"kinetic_aborb": 1.0,
		"explosive_absorb": 1.0,
		"drop_item_id": "sandstone",
		"terrain_int": 1,
		"color": Color(0.533, 0.212, 0.176)
	},
	
	"hematite":{
		"layer": "wall",
		"phase": "solid",
		"hp": 800,
		"kinetic_aborb": 1.0,
		"explosive_absorb": 0.5,
		"drop_item_id": "hematite",
		"terrain_int": 2,
		"color": Color.LIGHT_STEEL_BLUE
	},
	
	# Liquid Tile
	"crude_oil":{
		"layer": "wall",
		"phase": "liquid",
		"mass": 1000,
		"terrain_int": 3,
		"color": Color(0.149, 0.078, 0.310)
	},
	
	# Function Tile
	"building":{
		"layer": "building",
		"color": Color.YELLOW
	}
	
}











func get_tile(id: String) -> Dictionary:
	if tiles.has(id):
		return tiles[id]
	return {}
