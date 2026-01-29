class_name WallLayer
extends TileMapLayer

var layerdata:Dictionary[Vector2i, Dictionary]
var item_pickup_path = "res://items/item_pickup.tscn"
var map:Node2D

func _ready():
	map = get_parent()


func _process(delta):
	pass


func init_layerdata():
	for cell in get_used_cells():
		var tile_id = get_cell_source_id(cell)
		if tile_id == -1:
			continue
		
		var tile_matter = get_cell_tile_data(cell).get_custom_data("matter")
		var tile_info = TileDB.get_tile(tile_matter)
		var celldata:Dictionary
		if tile_info["phase"] == "solid":
			celldata = {
				"matter": tile_matter,
				"max_hp": tile_info["hp"],
				"current_hp": tile_info["hp"],
			}
		elif tile_info["phase"] == "liquid":
			celldata = {
				"matter": tile_matter,
				"mass": tile_info["mass"]
			}
		layerdata[cell] = celldata

func get_celldata(cell:Vector2i):
	if cell in layerdata:
		return layerdata[cell]
	else:
		return false

func damage_tile(cell:Vector2i, amount:int, dmg_type:String = ""):
	var kinetic_absorb = TileDB.get_tile(layerdata[cell]["matter"])["kinetic_aborb"]
	var explosive_absorb = TileDB.get_tile(layerdata[cell]["matter"])["explosive_absorb"]
	if dmg_type == "kinetic":
		amount *= kinetic_absorb
	elif dmg_type == "explosive":
		amount *= explosive_absorb
	
	layerdata[cell]["current_hp"] -= amount
	
	if layerdata[cell]["current_hp"] <= layerdata[cell]["max_hp"] * 0.5:
		pass
	
	# phase 2
	if layerdata[cell]["current_hp"] <= layerdata[cell]["max_hp"] * 0.25:
		pass
	
	# phase 3
	if layerdata[cell]["current_hp"] <= 0:
		destroy_tile(cell)
	
	#shard particle
	if randf_range(0, 1) < 0.1:
		if not get_cell_tile_data(cell):
			return
		var particle_path = get_cell_tile_data(cell).get_custom_data("particle_path")
		
		var shard = load(particle_path).instantiate()
		shard.position = map_to_local(cell)
		shard.emitting = true
		get_tree().current_scene.add_child(shard)

func destroy_tile(cell:Vector2i):
	#shard particle
	var particle_path = get_cell_tile_data(cell).get_custom_data("particle_path")
	var shard = load(particle_path).instantiate()
	shard.position = map_to_local(cell)
	shard.emitting = true
	get_tree().current_scene.add_child(shard)
	
	#pickup
	spawn_pickup(cell)
	
	erase_cell(cell)
	layerdata.erase(cell)
	BetterTerrain.update_terrain_cell(self, cell, true)


func spawn_pickup(cell:Vector2i):
	var item_id = layerdata[cell]["matter"]
	var pickup = load(item_pickup_path).instantiate() as Pickup
	pickup.item_id = item_id
	pickup.amount = 1
	pickup.position = map_to_local(cell)
	map.add_child(pickup)

# liquid Calculation
func get_connected_liquid(start_cell:Vector2i) -> Array[Vector2i]:
	if not get_celldata(start_cell):
		return []
	if TileDB.get_tile(layerdata[start_cell]["matter"])["phase"] != "liquid":
		return []
	var liquid = layerdata[start_cell]["matter"]
	var connected_liquid:Array[Vector2i] = []
	var directions = [
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN
	]
	var stack:Array[Vector2i] = [start_cell]
	var visited = {}
	
	while stack.size() > 0:
		var cell = stack.pop_back()
		if visited.has(cell):
			continue
		visited[cell] = true
		connected_liquid.append(cell)
		for dir in directions:
			var next = cell + dir
			if visited.has(next):
				continue
			if not get_celldata(next):
				continue
			if layerdata[next]["matter"] == liquid:
				stack.append(next)
	return connected_liquid

func get_total_liquid_mass(cells:Array[Vector2i]) -> float:
	var total_mass := 0.0
	for cell in cells:
		if not layerdata[cell]:
			return 0.0
		if not layerdata[cell]["mass"]:
			return 0.0
		total_mass += layerdata[cell]["mass"]
	return total_mass

func remove_liquid(cell:Vector2i, mass:float):
	if not get_celldata(cell):
		return
	if TileDB.get_tile(layerdata[cell]["matter"])["phase"] != "liquid":
		return
	var mass_left = mass
	while mass_left > 0:
		var farthest_cell = find_farthest_cell(cell, get_connected_liquid(cell))
		if farthest_cell == null:
			return
		elif layerdata[farthest_cell]["mass"] > mass_left:
			layerdata[farthest_cell]["mass"] -= mass_left
			return
		else:
			mass_left -= layerdata[farthest_cell]["mass"]
			erase_cell(farthest_cell)
			layerdata.erase(farthest_cell)
			BetterTerrain.update_terrain_cell(self, farthest_cell, true)
			

func add_liquid(cell:Vector2i, matter:String, mass:float):
	if get_celldata(cell):
		if layerdata[cell]["matter"] != matter:
			return
	var mass_left = mass
	var tile_added:Array[Vector2i] = []
	for c in get_connected_liquid(cell):
		if layerdata[c]["mass"] < 1000.0:
			var m = 1000.0 - layerdata[c]["mass"]
			if m >= mass_left:
				layerdata[c]["mass"] += mass_left
				return
			else:
				layerdata[c]["mass"] += m
				mass_left -= m
		if mass_left == 0:
			return
	
	while mass_left > 0:
		var connected_liquid = get_connected_liquid(cell)
		var closest_cell = find_closest_cell(cell, connected_liquid)
		if closest_cell == null:
			for c in connected_liquid:
				layerdata[c]["mass"] += mass / connected_liquid.size()
			return
		elif mass_left <= 1000.0:
			var celldata = {
				"matter": matter,
				"mass": mass_left
			}
			layerdata[closest_cell] = celldata
			mass_left = 0
		else:
			var celldata = {
				"matter": matter,
				"mass": 1000.0
			}
			layerdata[closest_cell] = celldata
			mass_left -= 1000.0
		tile_added.append(closest_cell)
	BetterTerrain.set_cells(self, tile_added, TileDB.get_tile(matter)["terrain_int"])
	BetterTerrain.update_terrain_cells(self, tile_added)


func find_farthest_cell(cell: Vector2i, from: Array[Vector2i]):
	var farthest = null
	var max_dist := -1.0
	for c in from:
		var d = abs(c.x - cell.x) + abs(c.y - cell.y)
		if d > max_dist:
			max_dist = d
			farthest = c
	return farthest

func find_closest_cell(cell: Vector2i, from: Array[Vector2i]):
	if from.is_empty():
		return cell
	var dirs = [
		Vector2i.UP,
		Vector2i.DOWN,
		Vector2i.LEFT,
		Vector2i.RIGHT
	]
	var closest = null
	var min_dist := INF
	for c in from:
		for d in dirs:
			var n = c + d
			if not get_cell_tile_data(n):
				var dist = abs(n.x - cell.x) + abs(n.y - cell.y)
				if dist < min_dist:
					min_dist = dist
					closest = n
	return closest
