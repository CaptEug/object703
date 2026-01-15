class_name WallLayer
extends TileMapLayer

var layerdata:Dictionary[Vector2i, Dictionary]


func _ready():
	pass # Replace with function body.



func _process(delta):
	pass


func init_layerdata():
	for cell in get_used_cells():
		var tile_id = get_cell_source_id(cell)
		if tile_id == -1:
			continue
		
		var tile_matter = get_cell_tile_data(cell).get_custom_data("matter")
		var tile_info = TileDB.get_tile(tile_matter)
		var celldata:Dictionary = {
			"matter": tile_matter,
			"max_hp": tile_info["hp"],
			"current_hp": tile_info["hp"],
		}
		layerdata[cell] = celldata


func get_celldata(cell:Vector2i):
	if cell in layerdata:
		return layerdata[cell]
	else:
		return false

func damage_tile(cell:Vector2i, amount:int):
	layerdata[cell]["current_hp"] -= amount
	if layerdata[cell]["current_hp"] <= layerdata[cell]["max_hp"] * 0.5:
		pass
	
	# phase 2
	if layerdata[cell]["current_hp"] <= layerdata[cell]["max_hp"] * 0.25:
		pass
	
	# phase 3
	if layerdata[cell]["current_hp"] <= 0:
		destroy_tile(cell)
	

func destroy_tile(cell:Vector2i):
	var tile_data = get_cell_tile_data(cell)
	erase_cell(cell)
	layerdata.erase(cell)
	BetterTerrain.update_terrain_cell(self, cell, true)
	
