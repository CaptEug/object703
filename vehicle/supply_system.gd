class_name SupplySystem
extends Node2D

@export var vehicle: Vehicle

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
	
	if vehicle == null or not vehicle.are_blocks_connected(from_storage, to_storage):
		return 0
	
	if not to_storage.accepts_item(item_name):
		return 0
	
	var available := mini(from_storage.get_item_count(item_name), amount)
	if available <= 0:
		return 0
	
	var free_load := to_storage.get_free_load()
	if free_load <= 0:
		return 0
	
	var item_w : int = ItemDB.get_item_by_name(item_name)["weight"]
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
	if vehicle == null:
		return []
	return vehicle.get_connected_blocks(block, false)


func get_connected_storages(block: Block) -> Array[ItemStorage]:
	if vehicle == null:
		return []
	
	var result: Array[ItemStorage] = []
	for other in vehicle.get_connected_blocks(block, true):
		if other is ItemStorage:
			result.append(other)
	
	return result


func get_total_item_amount(requester: Block, item_name: String) -> int:
	var storages: Array[ItemStorage] = get_connected_storages(requester)
	var total := 0
	
	for storage in storages:
		total += storage.get_item_count(item_name)
	
	return total
