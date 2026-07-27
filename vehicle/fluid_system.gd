class_name FluidSystem
extends Node2D

@export var vehicle: Vehicle

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
	if vehicle == null:
		return []
	return vehicle.get_connected_blocks(block, false)


func get_connected_storages(block: Block) -> Array:
	if vehicle == null:
		return []
	var result: Array = []
	for other in vehicle.get_connected_blocks(block, true):
		if other is LiquidStorage:
			result.append(other)
	
	return result
