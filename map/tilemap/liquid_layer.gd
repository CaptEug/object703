class_name LiquidLayer
extends TileMapLayer

var layerdata: Dictionary[Vector2i, Dictionary] = {}
@onready var gamemap: GameMap = get_parent()
var _bulk_edit_depth := 0
var _pending_visual_cells: Dictionary = {}


func begin_bulk_edit() -> void:
	_bulk_edit_depth += 1


func end_bulk_edit() -> void:
	_bulk_edit_depth = maxi(_bulk_edit_depth - 1, 0)
	if _bulk_edit_depth == 0:
		_flush_visual_updates()


func init_layerdata() -> void:
	layerdata.clear()
	for cell: Vector2i in get_used_cells():
		var tile_data := get_cell_tile_data(cell)
		if tile_data == null:
			continue
		var block_id := int(tile_data.get_custom_data("block_id"))
		if not BlockDB.is_liquid(block_id):
			continue
		layerdata[cell] = {
			"block_id": block_id,
			"mass": BlockDB.get_default_liquid_mass(block_id),
		}


func get_celldata(cell: Vector2i) -> Dictionary:
	return layerdata.get(cell, {})


func get_block_id_at(cell: Vector2i) -> int:
	return int(
		layerdata.get(cell, {}).get(
			"block_id",
			BlockDB.INVALID_BLOCK_ID
		)
	)


func get_visual_merge_data_at(cell: Vector2i) -> Dictionary:
	var block_id := get_block_id_at(cell)
	if not BlockDB.is_liquid(block_id):
		return {}
	return {
		"group": BlockVisualSystem.get_block_merge_group(block_id),
		"rotation": 0,
	}


func set_liquid_cell(
	cell: Vector2i,
	block_id: int,
	mass: float,
	update_visual: bool = true
) -> bool:
	if not BlockDB.is_liquid(block_id):
		return false
	if (
		gamemap != null
		and not gamemap.is_cell_in_world(cell)
	):
		return false
	if (
		gamemap != null
		and is_instance_valid(gamemap.world_blocks)
		and gamemap.world_blocks.get_block_id_at(cell)
		!= BlockDB.INVALID_BLOCK_ID
	):
		return false
	var cell_capacity := BlockDB.get_default_liquid_mass(block_id)
	layerdata[cell] = {
		"block_id": block_id,
		"mass": clampf(mass, 0.0, cell_capacity),
	}
	_queue_visual_refresh([cell])
	if update_visual:
		_update_minimap([cell])
	return true


func get_connected_liquid(start_cell: Vector2i) -> Array[Vector2i]:
	if not layerdata.has(start_cell):
		return []
	var liquid_block_id := int(layerdata[start_cell]["block_id"])
	var connected: Array[Vector2i] = []
	var stack: Array[Vector2i] = [start_cell]
	var visited := {}
	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		if visited.has(cell):
			continue
		visited[cell] = true
		connected.append(cell)
		for direction: Vector2i in [
			Vector2i.LEFT,
			Vector2i.RIGHT,
			Vector2i.UP,
			Vector2i.DOWN,
		]:
			var neighbor: Vector2i = cell + direction
			if (
				not visited.has(neighbor)
				and int(
					layerdata.get(neighbor, {}).get("block_id", -1)
				) == liquid_block_id
			):
				stack.append(neighbor)
	return connected


func get_total_liquid_mass(cells: Array[Vector2i]) -> float:
	var total_mass := 0.0
	for cell: Vector2i in cells:
		total_mass += float(layerdata.get(cell, {}).get("mass", 0.0))
	return total_mass


func remove_liquid(cell: Vector2i, mass: float) -> void:
	if mass <= 0.0 or not layerdata.has(cell):
		return
	var mass_left := mass
	while mass_left > 0.0:
		var connected := get_connected_liquid(cell)
		if connected.is_empty():
			return
		var farthest := _find_farthest_cell(cell, connected)
		var available := float(layerdata[farthest]["mass"])
		if available > mass_left:
			layerdata[farthest]["mass"] = available - mass_left
			return
		mass_left -= available
		erase_cell(farthest)
		layerdata.erase(farthest)
		_queue_visual_refresh([farthest])
		_update_minimap([farthest])


func add_liquid(cell: Vector2i, block_id: int, mass: float) -> void:
	if mass <= 0.0:
		return
	if not BlockDB.is_liquid(block_id):
		return
	if (
		layerdata.has(cell)
		and int(layerdata[cell]["block_id"]) != block_id
	):
		return
	var mass_left := mass
	var cellchanged: Array[Vector2i] = []
	var cell_capacity := BlockDB.get_default_liquid_mass(block_id)
	for connected_cell: Vector2i in get_connected_liquid(cell):
		var stored := float(layerdata[connected_cell]["mass"])
		var accepted := minf(cell_capacity - stored, mass_left)
		if accepted <= 0.0:
			continue
		layerdata[connected_cell]["mass"] = stored + accepted
		mass_left -= accepted
		cellchanged.append(connected_cell)
		if mass_left <= 0.0:
			break
	while mass_left > 0.0:
		var target := _find_closest_empty_cell(
			cell,
			get_connected_liquid(cell)
		)
		if target == WorldBlockLayer.INVALID_CELL:
			break
		var accepted := minf(mass_left, cell_capacity)
		set_liquid_cell(target, block_id, accepted, false)
		cellchanged.append(target)
		mass_left -= accepted
	if not cellchanged.is_empty():
		_queue_visual_refresh(cellchanged)
		_update_minimap(cellchanged)


func save_chunk(
	chunk_x: int,
	chunk_y: int,
	world_origin: Vector2i = Vector2i.ZERO
) -> PackedByteArray:
	const CHUNK_SIZE := 32
	var bytes := PackedByteArray()
	for ly in range(CHUNK_SIZE):
		for lx in range(CHUNK_SIZE):
			var cell := Vector2i(
				world_origin.x + chunk_x * CHUNK_SIZE + lx,
				world_origin.y + chunk_y * CHUNK_SIZE + ly
			)
			var state: Dictionary = layerdata.get(cell, {})
			var offset := bytes.size()
			bytes.resize(offset + 4)
			bytes.encode_u16(
				offset,
				int(state.get("block_id", 0))
			)
			bytes.encode_u16(
				offset + 2,
				clampi(roundi(float(state.get("mass", 0.0))), 0, 65535)
			)
	return bytes


func load_chunk(
	chunk_x: int,
	chunk_y: int,
	bytes: PackedByteArray,
	chunk_size: int,
	world_origin: Vector2i = Vector2i.ZERO
) -> void:
	var expected_size := chunk_size * chunk_size * 4
	if bytes.size() < expected_size:
		push_error("Liquid chunk is truncated.")
		return
	var index := 0
	var cellchanged: Array[Vector2i] = []
	for ly in range(chunk_size):
		for lx in range(chunk_size):
			var block_id := bytes.decode_u16(index)
			var mass := bytes.decode_u16(index + 2)
			index += 4
			if block_id <= 0:
				continue
			var cell := Vector2i(
				world_origin.x + chunk_x * chunk_size + lx,
				world_origin.y + chunk_y * chunk_size + ly
			)
			if set_liquid_cell(cell, block_id, float(mass), false):
				cellchanged.append(cell)
	if not cellchanged.is_empty():
		_queue_visual_refresh(cellchanged)


func _render_liquid_cell(cell: Vector2i) -> void:
	var block_id := get_block_id_at(cell)
	var variant := BlockVisualSystem.resolve_variant(
		self,
		cell,
		block_id,
		0
	)
	if variant.is_empty():
		erase_cell(cell)
		return
	set_cell(
		cell,
		int(variant["source_id"]),
		variant["atlas_coordinates"],
		int(variant.get("alternative", 0))
	)


func _queue_visual_refresh(cells: Array[Vector2i]) -> void:
	for cell: Vector2i in cells:
		_pending_visual_cells[cell] = true
		for direction: Vector2i in (
			BlockVisualSystem.NEIGHBOR_DIRECTIONS
		):
			_pending_visual_cells[cell + direction] = true
	if _bulk_edit_depth == 0:
		_flush_visual_updates()


func _flush_visual_updates() -> void:
	for cell: Vector2i in _pending_visual_cells:
		if layerdata.has(cell):
			_render_liquid_cell(cell)
	_pending_visual_cells.clear()


func _find_farthest_cell(
	origin: Vector2i,
	cells: Array[Vector2i]
) -> Vector2i:
	var result: Vector2i = cells[0]
	var max_distance := -1
	for cell: Vector2i in cells:
		var distance: int = (
			abs(cell.x - origin.x) + abs(cell.y - origin.y)
		)
		if distance > max_distance:
			max_distance = distance
			result = cell
	return result


func _find_closest_empty_cell(
	origin: Vector2i,
	cells: Array[Vector2i]
) -> Vector2i:
	if cells.is_empty() and not layerdata.has(origin):
		return origin
	var result: Vector2i = WorldBlockLayer.INVALID_CELL
	var min_distance := 2147483647
	for cell: Vector2i in cells:
		for direction: Vector2i in [
			Vector2i.UP,
			Vector2i.DOWN,
			Vector2i.LEFT,
			Vector2i.RIGHT,
		]:
			var neighbor: Vector2i = cell + direction
			if layerdata.has(neighbor):
				continue
			var distance: int = (
				abs(neighbor.x - origin.x)
				+ abs(neighbor.y - origin.y)
			)
			if distance < min_distance:
				min_distance = distance
				result = neighbor
	return result


func _update_minimap(cells: Array[Vector2i]) -> void:
	if gamemap == null or not is_instance_valid(gamemap.minimap):
		return
	gamemap.minimap.update_cellmap(cells)
