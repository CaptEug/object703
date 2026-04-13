class_name FluidSystem
extends Node2D

@export var vehicle: Vehicle

var pipe_scene: PackedScene = load("res://blocks/logistic/liquid_pipe.tscn")
var pipe_grid: Dictionary = {}    # cell -> Pipe
var pipe_groups: Array = []    # Array[Array[Vector2i]]
var block_group_map: Dictionary[Block, int] = {}    # Block -> group_index

const DIRS := [
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT
]


# =========================
# PIPE EDITING
# =========================

func can_place_pipe(cell: Vector2i) -> bool:
	# must be on block
	if not vehicle.grid.has(cell):
		return false
	
	# already occupied
	if pipe_grid.has(cell):
		return false
	
	return true


func place_pipe(cell: Vector2i) -> void:
	if not can_place_pipe(cell):
		return
	
	var pipe := pipe_scene.instantiate() as Pipe
	pipe.update_transform(vehicle, cell, 0)
	add_child(pipe)
	
	pipe_grid[cell] = pipe
	rebuild_pipe_network()


func remove_pipe(cell: Vector2i) -> void:
	if not pipe_grid.has(cell):
		return
	
	pipe_grid[cell].queue_free()
	pipe_grid.erase(cell)
	rebuild_pipe_network()


func clear_pipes() -> void:
	for pipe in pipe_grid.values():
		pipe.queue_free()
	
	pipe_grid.clear()
	rebuild_pipe_network()


func update_pipe_visuals() -> void:
	for pipe in pipe_grid.values():
		pipe.update_sprite()


# =========================
# GROUP BUILD
# =========================

func rebuild_pipe_groups() -> Array:
	update_pipe_visuals()
	
	var groups: Array = []
	var visited := {}
	
	for start_cell in pipe_grid.keys():
		if visited.has(start_cell):
			continue
		var group: Array[Vector2i] = []
		var queue: Array[Vector2i] = [start_cell]
		visited[start_cell] = true
		while queue.size() > 0:
			var cell: Vector2i = queue.pop_front()
			group.append(cell)
			for dir in DIRS:
				var next: Vector2i = cell + dir
				if not pipe_grid.has(next):
					continue
				if visited.has(next):
					continue
				visited[next] = true
				queue.append(next)
		
		groups.append(group)
	
	return groups


func rebuild_pipe_network() -> void:
	pipe_groups = rebuild_pipe_groups()
	block_group_map.clear()
	
	for group_index in range(pipe_groups.size()):
		var group_set := {}
		for cell in pipe_groups[group_index]:
			group_set[cell] = true
		for block in vehicle.blocks:
			if "liquid_port" in block:
				var world_port: Vector2i = block.get_transformed_cell(block.liquid_port)
				if group_set.has(world_port):
					block_group_map[block] = group_index


# =========================
# LIQUID SUPPLY
# =========================

func can_supply_liquids(requester: Block, liquids: Dictionary) -> bool:
	for liquid_type in liquids.keys():
		var amount: float = liquids[liquid_type]
		if not can_supply_liquid(requester, liquid_type, amount):
			return false
	return true


func can_supply_liquid(requester: Block, liquid_type: String, amount: float) -> bool:
	var storages: Array = get_connected_storages(requester)
	if storages.is_empty():
		return false
	
	var total_available := 0.0
	
	for storage in storages:
		if storage.liquid == liquid_type:
			var available : float = storage.stored
			total_available += available
	
	return total_available >= amount


func supply_liquids(requester: Block, liquids: Dictionary) -> bool:
	if liquids.is_empty():
		return true
	
	if not can_supply_liquids(requester, liquids):
		return false
	
	for liquid_type in liquids.keys():
		var amount: float = liquids[liquid_type]
		if not supply_liquid(requester, liquid_type, amount):
			push_warning("supply_liquids failed after can_supply_liquids passed")
			return false
	
	return true


func supply_liquid(requester: Block, liquid_type: String, amount: float) -> bool:
	var storages: Array = get_connected_storages(requester)
	if storages.is_empty():
		return false
	
	var valid_storages: Array[LiquidStorage] = []
	
	for storage in storages:
		if storage.liquid != liquid_type:
			continue
		if storage.stored <= 0.0:
			continue
		valid_storages.append(storage)
	
	
	var remaining := amount
	
	for storage in valid_storages:
		if remaining <= 0.0:
			break
		var taken := storage.take_liquid(liquid_type, remaining)
		remaining -= taken
	
	
	return remaining <= 0.0


# =========================
# LIQUID INSERT (ADD)
# =========================

func receive_liquids(requester: Block, liquids: Dictionary) -> float:
	var total_added := 0.0
	
	for liquid_type in liquids.keys():
		var amount: float = liquids[liquid_type]
		var added := receive_liquid(requester, liquid_type, amount)
		total_added += added
	
	return total_added


func receive_liquid(requester: Block, liquid_type: String, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var storages: Array[LiquidStorage] = get_connected_storages(requester)
	if storages.is_empty():
		return 0.0
	
	var remaining := amount
	
	# pass 1: fill storages already holding same liquid (no mixing)
	for storage in storages:
		if remaining <= 0.0:
			break
		if storage.liquid != liquid_type:
			continue
		
		var accepted := storage.add_liquid(liquid_type, remaining)
		remaining -= accepted
	
	# pass 2: fill empty storages
	for storage in storages:
		if remaining <= 0.0:
			break
		if storage.stored > 0.0:
			continue  # skip non-empty (already handled above)
		
		var accepted := storage.add_liquid(liquid_type, remaining)
		remaining -= accepted
	
	return amount - remaining


# =========================
# HELPERS
# =========================

func get_connected_blocks_excluding_self(block: Block) -> Array[Block]:
	var group_index : int = block_group_map.get(block, -1)
	if group_index == -1:
		return []
	var result: Array[Block] = []
	for other in block_group_map.keys():
		if other == block:
			continue
		if block_group_map[other] == group_index:
			result.append(other)
	return result


func get_connected_storages(block: Block) -> Array:
	var group_index : int = block_group_map.get(block, -1)
	if group_index == -1:
		return []
	var result: Array = []
	for other in block_group_map.keys():
		if block_group_map[other] != group_index:
			continue
		if other is LiquidStorage:
			result.append(other)
	
	return result
