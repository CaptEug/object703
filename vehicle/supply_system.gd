class_name SupplySystem
extends Node2D

@export var vehicle: Vehicle

var tube_scene: PackedScene = load("res://blocks/logistic/supply_tube.tscn")
var tube_grid: Dictionary = {}    # cell -> tube
var tube_groups: Array = []       # Array[Array[Vector2i]]
var block_group_map: Dictionary = {}    # Block -> group_index

const DIRS := [
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT
]


# =========================
# TUBE EDITING
# =========================

func can_place_tube(cell: Vector2i) -> bool:
	# must be on block
	if not vehicle.grid.has(cell):
		return false
	
	# already occupied
	if tube_grid.has(cell):
		return false
	
	return true


func place_tube(cell: Vector2i) -> void:
	if not can_place_tube(cell):
		return
	
	var tube := tube_scene.instantiate()
	tube.update_transform(vehicle, cell, 0)
	add_child(tube)
	
	tube_grid[cell] = tube
	rebuild_tube_network()


func remove_tube(cell: Vector2i) -> void:
	if not tube_grid.has(cell):
		return
	
	tube_grid[cell].queue_free()
	tube_grid.erase(cell)
	rebuild_tube_network()


func clear_tubes() -> void:
	for tube in tube_grid.values():
		tube.queue_free()
	
	tube_grid.clear()
	rebuild_tube_network()


func update_tube_visuals() -> void:
	for tube in tube_grid.values():
		tube.update_sprite()


# =========================
# GROUP BUILD
# =========================

func rebuild_tube_groups() -> Array:
	update_tube_visuals()
	
	var groups: Array = []
	var visited := {}
	
	for start_cell in tube_grid.keys():
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
				if not tube_grid.has(next):
					continue
				if visited.has(next):
					continue
				
				visited[next] = true
				queue.append(next)
		
		groups.append(group)
	
	return groups


func rebuild_tube_network() -> void:
	tube_groups = rebuild_tube_groups()
	block_group_map.clear()
	
	for group_index in range(tube_groups.size()):
		var group_set := {}
		
		for cell in tube_groups[group_index]:
			group_set[cell] = true
		
		for block in vehicle.blocks:
			if "supply_port" in block:
				var world_port: Vector2i = block.get_transformed_cell(block.supply_port)
				if group_set.has(world_port):
					block_group_map[block] = group_index


# =========================
# ITEM SUPPLY
# =========================

func can_supply_items(requester: Block, item_requirements: Dictionary) -> bool:
	for item_name in item_requirements.keys():
		var amount: int = int(item_requirements[item_name])
		if not can_supply_item(requester, item_name, amount):
			return false
	
	return true


func can_supply_item(requester: Block, item_name: String, amount: int) -> bool:
	if amount <= 0:
		return true
	
	var storages: Array[ItemStorage] = get_connected_storages(requester)
	if storages.is_empty():
		return false
	
	var total_available := 0
	
	for storage in storages:
		total_available += storage.get_item_count(item_name)
	
	return total_available >= amount


func supply_items(requester: Block, item_requirements: Dictionary) -> bool:
	if item_requirements.is_empty():
		return true
	
	if not can_supply_items(requester, item_requirements):
		return false
	
	for item_name in item_requirements.keys():
		var amount: int = int(item_requirements[item_name])
		if not supply_item(requester, item_name, amount):
			push_warning("supply_items failed after can_supply_items passed")
			return false
	
	return true


func supply_item(requester: Block, item_name: String, amount: int) -> bool:
	if amount <= 0:
		return true
	
	var storages: Array[ItemStorage] = get_connected_storages(requester)
	if storages.is_empty():
		return false
	
	var remaining := amount
	
	for storage in storages:
		if remaining <= 0:
			break
		
		var taken := storage.take_item(item_name, remaining)
		remaining -= taken
	
	return remaining <= 0


# =========================
# ITEM INSERT (ADD)
# =========================

func receive_items(requester: Block, incoming_items: Dictionary) -> int:
	var total_added := 0
	
	for item_name in incoming_items.keys():
		var amount: int = int(incoming_items[item_name])
		total_added += receive_item(requester, item_name, amount)
	
	return total_added


func receive_item(requester: Block, item_name: String, amount: int) -> int:
	if amount <= 0:
		return 0
	
	var storages: Array[ItemStorage] = get_connected_storages(requester)
	if storages.is_empty():
		return 0
	
	var remaining := amount
	
	# pass 1: storages that already hold this item
	for storage in storages:
		if remaining <= 0:
			break
		if storage.get_item_count(item_name) <= 0:
			continue
		
		var accepted := storage.add_item(item_name, remaining)
		remaining -= accepted
	
	# pass 2: other storages that can accept this item
	for storage in storages:
		if remaining <= 0:
			break
		if storage.get_item_count(item_name) > 0:
			continue
		if not storage.accepts_item(item_name):
			continue
		
		var accepted := storage.add_item(item_name, remaining)
		remaining -= accepted
	
	return amount - remaining


# =========================
# ITEM TRANSFER
# =========================

func transfer_item(from_storage: ItemStorage, to_storage: ItemStorage, item_name: String, amount: int) -> int:
	if amount <= 0:
		return 0
	
	var from_group: int = block_group_map.get(from_storage, -1)
	var to_group: int = block_group_map.get(to_storage, -1)
	
	if from_group == -1 or to_group == -1 or from_group != to_group:
		return 0
	
	if not to_storage.accepts_item(item_name):
		return 0
	
	var available := mini(from_storage.get_item_count(item_name), amount)
	if available <= 0:
		return 0
	
	var free_load := to_storage.get_free_load()
	if free_load <= 0:
		return 0
	
	var item_w : int = ItemDB.get_item(item_name)["weight"]
	var vacancy := floori(free_load/item_w)
	
	var move_amount : int = min(available, vacancy)
	if move_amount <= 0:
		return 0
	
	var taken := from_storage.take_item(item_name, move_amount)
	var added := to_storage.add_item(item_name, taken)
	
	# rollback safety
	if added < taken:
		from_storage.add_item(item_name, taken - added)
	
	return added


# =========================
# HELPERS
# =========================

func get_connected_blocks_excluding_self(block: Block) -> Array[Block]:
	var group_index: int = block_group_map.get(block, -1)
	if group_index == -1:
		return []
	
	var result: Array[Block] = []
	for other in block_group_map.keys():
		if other == block:
			continue
		if block_group_map[other] == group_index:
			result.append(other)
	
	return result


func get_connected_storages(block: Block) -> Array[ItemStorage]:
	var group_index: int = block_group_map.get(block, -1)
	if group_index == -1:
		return []
	
	var result: Array[ItemStorage] = []
	for other in block_group_map.keys():
		if block_group_map[other] != group_index:
			continue
		if other == block:
			continue
		if other is ItemStorage:
			result.append(other)
	
	return result


func get_total_item_amount(requester: Block, item_name: String) -> int:
	var storages: Array[ItemStorage] = get_connected_storages(requester)
	var total := 0
	
	for storage in storages:
		total += storage.get_item_count(item_name)
	
	return total
