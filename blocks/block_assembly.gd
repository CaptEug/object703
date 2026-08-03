class_name BlockAssembly
extends RefCounted

var host: Object
var owner_id: StringName = &"player"
var blocks: Array[Block] = []

var control_blocks: Array[ControlBlock] = []
var active_control_block: ControlBlock
var item_storages: Array[ItemStorage] = []
var liquid_storages: Array[LiquidStorage] = []
var engines: Array[PowerPack] = []
var power_consumers: Array[Block] = []


func _init(assembly_host: Object = null) -> void:
	host = assembly_host


func rebuild(
	new_blocks: Array[Block],
	preferred_control: ControlBlock = active_control_block
) -> void:
	for previous_block: Block in blocks:
		if (
			is_instance_valid(previous_block)
			and previous_block.assembly == self
		):
			previous_block.assembly = null
	blocks.clear()
	control_blocks.clear()
	item_storages.clear()
	liquid_storages.clear()
	engines.clear()
	power_consumers.clear()
	for block: Block in new_blocks:
		if not is_instance_valid(block):
			continue
		blocks.append(block)
		block.assembly = self
		if block is ControlBlock:
			control_blocks.append(block as ControlBlock)
		if block is ItemStorage:
			item_storages.append(block as ItemStorage)
		elif block is LiquidStorage:
			liquid_storages.append(block as LiquidStorage)
		if block is PowerPack:
			engines.append(block as PowerPack)
		elif block.is_power_consumer():
			power_consumers.append(block)

	if (
		is_instance_valid(preferred_control)
		and control_blocks.has(preferred_control)
	):
		active_control_block = preferred_control
	elif control_blocks.is_empty():
		active_control_block = null
	else:
		active_control_block = control_blocks[0]


func has_control_block(control_block: ControlBlock) -> bool:
	return (
		is_instance_valid(control_block)
		and control_blocks.has(control_block)
	)


func is_active_control_block(control_block: ControlBlock) -> bool:
	return has_control_block(control_block) and (
		active_control_block == control_block
	)


func set_active_control_block(control_block: ControlBlock) -> bool:
	if not has_control_block(control_block):
		return false
	active_control_block = control_block
	return true


func get_drive_input() -> Dictionary:
	if not is_instance_valid(active_control_block):
		return {"move": 0.0, "pivot": 0.0}
	return active_control_block.get_drive_command()


func has_aim_command() -> bool:
	return (
		is_instance_valid(active_control_block)
		and active_control_block.has_aim_command()
	)


func get_aim_target() -> Vector2:
	if not is_instance_valid(active_control_block):
		return Vector2.ZERO
	return active_control_block.get_aim_target()


func get_fire_command() -> bool:
	return (
		is_instance_valid(active_control_block)
		and active_control_block.get_fire_command()
	)


func get_construction_storages() -> Array[ItemStorage]:
	var result: Array[ItemStorage] = []
	for storage: ItemStorage in item_storages:
		if storage.storage_kind == ItemStorage.StorageKind.CARGO:
			result.append(storage)
	return result


func can_supply_item(
	_requester: Block,
	item_name: String,
	amount: int
) -> bool:
	if amount <= 0:
		return true
	var available := 0
	for storage: ItemStorage in item_storages:
		available += storage.get_item_count(item_name)
		if available >= amount:
			return true
	return false


func supply_item(
	requester: Block,
	item_name: String,
	amount: int
) -> bool:
	if amount <= 0:
		return true
	if not can_supply_item(requester, item_name, amount):
		return false
	var remaining := amount
	for storage: ItemStorage in item_storages:
		remaining -= storage.take_item(item_name, remaining)
		if remaining <= 0:
			return true
	return false


func can_receive_item(
	_requester: Block,
	item_name: String,
	amount: int = 1
) -> bool:
	if amount <= 0:
		return true
	var item_data := ItemDB.get_item_by_name(item_name)
	var item_weight := float(item_data.get("weight", 0.0))
	if item_data.is_empty() or item_weight <= 0.0:
		return false
	var capacity := 0
	for storage: ItemStorage in item_storages:
		if not storage.accepts_item(item_name):
			continue
		capacity += floori(storage.get_free_load() / item_weight)
		if capacity >= amount:
			return true
	return false


func receive_item(
	_requester: Block,
	item_name: String,
	amount: int
) -> int:
	if amount <= 0:
		return 0
	var remaining := amount
	for storage: ItemStorage in item_storages:
		if remaining <= 0:
			break
		if storage.get_item_count(item_name) <= 0:
			continue
		remaining -= storage.add_item(item_name, remaining)
	for storage: ItemStorage in item_storages:
		if remaining <= 0:
			break
		if storage.get_item_count(item_name) > 0:
			continue
		remaining -= storage.add_item(item_name, remaining)
	return amount - remaining


func can_supply_liquids(
	_requester: Block,
	liquid_requests: Dictionary
) -> bool:
	for liquid_name: String in liquid_requests:
		var required := float(liquid_requests[liquid_name])
		var available := 0.0
		for storage: LiquidStorage in liquid_storages:
			if storage.liquid == liquid_name:
				available += storage.stored
		if available < required:
			return false
	return true


func supply_liquids(
	requester: Block,
	liquid_requests: Dictionary
) -> bool:
	if not can_supply_liquids(requester, liquid_requests):
		return false
	for liquid_name: String in liquid_requests:
		var remaining := float(liquid_requests[liquid_name])
		for storage: LiquidStorage in liquid_storages:
			if storage.liquid != liquid_name:
				continue
			remaining -= storage.take_liquid(liquid_name, remaining)
			if remaining <= 0.0:
				break
	return true


func receive_liquid(
	_requester: Block,
	liquid_name: String,
	amount: float
) -> float:
	if amount <= 0.0:
		return 0.0
	var remaining := amount
	for storage: LiquidStorage in liquid_storages:
		if remaining <= 0.0:
			break
		if storage.liquid != liquid_name:
			continue
		remaining -= storage.add_liquid(liquid_name, remaining)
	for storage: LiquidStorage in liquid_storages:
		if remaining <= 0.0:
			break
		if storage.stored > 0.0:
			continue
		remaining -= storage.add_liquid(liquid_name, remaining)
	return amount - remaining


func get_device_power_demand() -> float:
	var demand := 0.0
	for device: Block in power_consumers:
		demand += maxf(device.get_power_demand(), 0.0)
	return demand


func set_engine_targets(total_demand: float) -> void:
	var active: Array[PowerPack] = engines.duplicate()
	for engine: PowerPack in engines:
		engine.power_target = 0.0
	var remaining := maxf(total_demand, 0.0)
	while remaining > 0.0 and not active.is_empty():
		var share := remaining / float(active.size())
		var next_active: Array[PowerPack] = []
		var assigned := 0.0
		for engine: PowerPack in active:
			var headroom := maxf(
				engine.max_power - engine.power_target,
				0.0
			)
			var amount := minf(share, headroom)
			engine.power_target += amount
			assigned += amount
			if engine.power_target < engine.max_power:
				next_active.append(engine)
		if assigned <= 0.0:
			break
		remaining -= assigned
		active = next_active


func get_available_engine_power() -> float:
	var result := 0.0
	for engine: PowerPack in engines:
		result += maxf(engine.power_output, 0.0)
	return result


func distribute_device_power(power_budget: float) -> float:
	var demands: Dictionary[Block, float] = {}
	var total_demand := 0.0
	for device: Block in power_consumers:
		var demand := maxf(device.get_power_demand(), 0.0)
		demands[device] = demand
		total_demand += demand
	var used_power := minf(maxf(power_budget, 0.0), total_demand)
	var supply_ratio := (
		0.0
		if total_demand <= 0.0
		else used_power / total_demand
	)
	for device: Block in power_consumers:
		device.set_supplied_power(
			float(demands[device]) * supply_ratio
		)
	return used_power


func update_stationary_power() -> void:
	var demand := get_device_power_demand()
	set_engine_targets(demand)
	distribute_device_power(get_available_engine_power())
