class_name WallLayer
extends TileMapLayer

const INVALID_CELL := Vector2i(-2147483648, -2147483648)

var layerdata:Dictionary[Vector2i, Dictionary]
@onready var gamemap:GameMap = get_parent()

func _ready():
	add_to_group("environment_wall_layers")


func _process(_delta):
	pass


func init_layerdata():
	for cell in get_used_cells():
		var tile_id = get_cell_source_id(cell)
		if tile_id == -1:
			continue
		
		var tile_type_id := int(
			get_cell_tile_data(cell).get_custom_data("tile_id")
		)
		var tile_info := TileDB.get_tile(tile_type_id)
		if tile_info.is_empty():
			push_error("Unknown TileDB ID %d at %s." % [
				tile_type_id,
				cell,
			])
			continue
		var celldata:Dictionary
		if tile_info["phase"] == "solid":
			celldata = {
				"tile_id": tile_type_id,
				"data": tile_info["hp"],
			}
		elif tile_info["phase"] == "liquid":
			celldata = {
				"tile_id": tile_type_id,
				"data": tile_info["mass"]
			}
		layerdata[cell] = celldata

func get_celldata(cell:Vector2i) -> Dictionary:
	return layerdata.get(cell, {})


func get_solid_cell_at_world_position(
	world_position: Vector2,
	travel_direction: Vector2 = Vector2.ZERO
) -> Vector2i:
	var sample_position := world_position
	if not travel_direction.is_zero_approx():
		sample_position += travel_direction.normalized()
	var cell := local_to_map(to_local(sample_position))
	if _is_solid_cell(cell):
		return cell
	return INVALID_CELL


func damage_tile(
	cell: Vector2i,
	amount: float,
	damage_type: StringName = &""
) -> Dictionary:
	var result := {
		"hit": false,
		"destroyed": false,
		"damage_applied": 0.0,
		"damage_consumed": 0.0,
	}
	if amount <= 0.0 or not _is_solid_cell(cell):
		return result

	var cell_data: Dictionary = layerdata[cell]
	var tile_info := TileDB.get_tile(int(cell_data["tile_id"]))
	var hp_before := maxf(float(cell_data.get("data", 0.0)), 0.0)
	var multiplier := _get_damage_multiplier(tile_info, damage_type)
	result["hit"] = true

	if multiplier <= 0.0:
		result["damage_consumed"] = amount
		return result

	var damage_applied := minf(amount * multiplier, hp_before)
	var damage_consumed := minf(amount, hp_before / multiplier)
	cell_data["data"] = hp_before - damage_applied
	result["damage_applied"] = damage_applied
	result["damage_consumed"] = damage_consumed

	if float(cell_data["data"]) <= 0.001:
		result["destroyed"] = destroy_tile(cell)
	elif randf() < 0.1:
		_spawn_tile_shards(cell, tile_info)
	return result


func apply_radial_damage(
	world_position: Vector2,
	radius_tiles: int,
	max_damage: float
) -> int:
	if max_damage <= 0.0:
		return 0
	var center_cell := local_to_map(to_local(world_position))
	if radius_tiles <= 0:
		var direct_result := damage_tile(
			center_cell,
			max_damage,
			&"EXPLOSIVE"
		)
		return 1 if direct_result["hit"] else 0

	var damaged_cells := 0
	for y in range(-radius_tiles, radius_tiles + 1):
		for x in range(-radius_tiles, radius_tiles + 1):
			var cell := center_cell + Vector2i(x, y)
			if not _is_solid_cell(cell):
				continue
			var cell_world := to_global(map_to_local(cell))
			var distance_tiles := (
				world_position.distance_to(cell_world)
				/ float(Globals.TILE_SIZE)
			)
			if distance_tiles > float(radius_tiles):
				continue
			var factor := 1.0 - distance_tiles / float(radius_tiles)
			var damage := max_damage * factor
			if damage <= 0.0:
				continue
			var result := damage_tile(cell, damage, &"EXPLOSIVE")
			if result["hit"]:
				damaged_cells += 1
	return damaged_cells


func destroy_tile(cell: Vector2i) -> bool:
	if not _is_solid_cell(cell):
		return false
	var tile_info := TileDB.get_tile(int(layerdata[cell]["tile_id"]))
	_spawn_tile_shards(cell, tile_info)
	erase_cell(cell)
	layerdata.erase(cell)
	BetterTerrain.update_terrain_cell(self, cell, true)
	_update_minimap([cell])
	return true


func _is_solid_cell(cell: Vector2i) -> bool:
	var cell_data := get_celldata(cell)
	if cell_data.is_empty():
		return false
	var tile_info := TileDB.get_tile(int(cell_data.get("tile_id", -1)))
	return tile_info.get("phase", "") == "solid"


func _get_damage_multiplier(
	tile_info: Dictionary,
	damage_type: StringName
) -> float:
	match String(damage_type).to_upper():
		"KINETIC":
			return maxf(
				float(tile_info.get("kinetic_damage_multiplier", 1.0)),
				0.0
			)
		"EXPLOSIVE":
			return maxf(
				float(tile_info.get("explosive_damage_multiplier", 1.0)),
				0.0
			)
	return 1.0


func _spawn_tile_shards(cell: Vector2i, tile_info: Dictionary) -> void:
	var particle_path := str(tile_info.get("particle_path", ""))
	if particle_path.is_empty():
		return
	var particle_scene := load(particle_path) as PackedScene
	if particle_scene == null:
		return
	var shard := particle_scene.instantiate() as GPUParticles2D
	if shard == null:
		return
	shard.global_position = to_global(map_to_local(cell))
	shard.emitting = true
	get_tree().current_scene.add_child(shard)


func _update_minimap(cells: Array[Vector2i]) -> void:
	if gamemap == null or not is_instance_valid(gamemap.minimap):
		return
	gamemap.minimap.update_cellmap(cells)

# liquid Calculation
func get_connected_liquid(start_cell:Vector2i) -> Array[Vector2i]:
	if not get_celldata(start_cell):
		return []
	if TileDB.get_tile(layerdata[start_cell]["tile_id"])["phase"] != "liquid":
		return []
	var liquid_tile_id = layerdata[start_cell]["tile_id"]
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
			if layerdata[next]["tile_id"] == liquid_tile_id:
				stack.append(next)
	return connected_liquid

func get_total_liquid_mass(cells:Array[Vector2i]) -> float:
	var total_mass := 0.0
	for cell in cells:
		if not layerdata[cell]:
			return 0.0
		if not layerdata[cell]["data"]:
			return 0.0
		total_mass += layerdata[cell]["data"]
	return total_mass

func remove_liquid(cell:Vector2i, mass:float):
	if not get_celldata(cell):
		return
	if TileDB.get_tile(layerdata[cell]["tile_id"])["phase"] != "liquid":
		return
	var mass_left = mass
	while mass_left > 0:
		var farthest_cell = find_farthest_cell(cell, get_connected_liquid(cell))
		if farthest_cell == null:
			return
		elif layerdata[farthest_cell]["data"] > mass_left:
			layerdata[farthest_cell]["data"] -= mass_left
			return
		else:
			mass_left -= layerdata[farthest_cell]["data"]
			erase_cell(farthest_cell)
			layerdata.erase(farthest_cell)
			BetterTerrain.update_terrain_cell(self, farthest_cell, true)
			_update_minimap([farthest_cell])

func add_liquid(cell: Vector2i, tile_id: int, mass: float):
	if (
		not TileDB.has_tile(tile_id)
		or TileDB.get_tile(tile_id).get("phase", "") != "liquid"
	):
		return
	if get_celldata(cell):
		if layerdata[cell]["tile_id"] != tile_id:
			return
	var mass_left = mass
	var tile_added:Array[Vector2i] = []
	for c in get_connected_liquid(cell):
		if layerdata[c]["data"] < 1000.0:
			var m = 1000.0 - layerdata[c]["data"]
			if m >= mass_left:
				layerdata[c]["data"] += mass_left
				return
			else:
				layerdata[c]["data"] += m
				mass_left -= m
		if mass_left == 0:
			return
	
	while mass_left > 0:
		var connected_liquid = get_connected_liquid(cell)
		var closest_cell = find_closest_cell(cell, connected_liquid)
		if closest_cell == null:
			for c in connected_liquid:
				layerdata[c]["data"] += mass / connected_liquid.size()
			return
		elif mass_left <= 1000.0:
			var celldata = {
				"tile_id": tile_id,
				"data": mass_left
			}
			layerdata[closest_cell] = celldata
			mass_left = 0
		else:
			var celldata = {
				"tile_id": tile_id,
				"data": 1000.0
			}
			layerdata[closest_cell] = celldata
			mass_left -= 1000.0
		tile_added.append(closest_cell)
	if !tile_added.is_empty():
		BetterTerrain.set_cells(self, tile_added, tile_id)
		BetterTerrain.update_terrain_cells(self, tile_added)
		_update_minimap(tile_added)

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

# SAVE AND LOAD

func save_chunk(chunk_x: int, chunk_y: int) -> PackedByteArray:
	const CHUNK_SIZE := 32
	var bytes := PackedByteArray()
	for ly in range(CHUNK_SIZE):
		for lx in range(CHUNK_SIZE):
			var x := chunk_x * CHUNK_SIZE + lx
			var y := chunk_y * CHUNK_SIZE + ly
			var cell := Vector2i(x, y)
			var celldata = get_celldata(cell)
			# --- terrain (u8) ---
			bytes.append(
				TileDB.EMPTY_TILE_ID
				if celldata.is_empty()
				else int(celldata["tile_id"])
			)
	
			# --- data (u16) ---
			var data := 0
			if not celldata.is_empty():
				data = celldata.get("data", 0)
			var offset := bytes.size()
			bytes.resize(offset + 2)
			bytes.encode_u16(offset, data)    
	return bytes

func load_chunk(chunk_x:int, chunk_y:int, bytes:PackedByteArray, CHUNK_SIZE:int):
	var i := 0
	for ly in range(CHUNK_SIZE):
		for lx in range(CHUNK_SIZE):
			var tile_id := bytes.decode_u8(i); i += 1
			var data := bytes.decode_u16(i); i += 2

			if tile_id == TileDB.EMPTY_TILE_ID:
				continue
			if not TileDB.has_tile(tile_id):
				push_error("Unknown saved TileDB ID %d." % tile_id)
				continue

			var x := chunk_x * CHUNK_SIZE + lx
			var y := chunk_y * CHUNK_SIZE + ly
			var cell := Vector2i(x, y)
			BetterTerrain.set_cell(self, cell, tile_id)
			layerdata[cell] = {
				"tile_id": tile_id,
				"data": data
			}
	var rect := Rect2i(Vector2i(chunk_x * CHUNK_SIZE, chunk_y * CHUNK_SIZE), Vector2i(CHUNK_SIZE, CHUNK_SIZE))
	BetterTerrain.update_terrain_area(self, rect)
