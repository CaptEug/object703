extends Node

var tiles = {
	"sandstone":{
		"layer": "wall",
		"hp": 400,
		"kinetic_aborb": 1.0,
		"explosive_absorb": 1.0,
		"drop_item_id": "sandstone"
	},
	
	"hematite":{
		"layer": "wall",
		"hp": 800,
		"kinetic_aborb": 1.0,
		"explosive_absorb": 0.5,
		"drop_item_id": "hematite"
	}
}











func get_tile(id: String) -> Dictionary:
	if tiles.has(id):
		return tiles[id]
	return {}
