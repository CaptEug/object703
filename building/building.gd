class_name Building
extends RefCounted

var building_id := 0
var building_name := "New Building"
var block_anchors: Array[Vector2i] = []
var occupied_cells: Array[Vector2i] = []
var functional_blocks: Array[Block] = []
var workshop_blocks: Array[WorkshopBlock] = []
var world_block_layer: WorldBlockLayer
var block_assembly: BlockAssembly

var _owner_id: StringName = &"player"
var owner_id: StringName:
	get:
		return block_assembly.owner_id if block_assembly != null else _owner_id
	set(value):
		_owner_id = value
		if block_assembly != null:
			block_assembly.owner_id = value

var control_blocks: Array[ControlBlock]:
	get:
		return (
			block_assembly.control_blocks
			if block_assembly != null
			else []
		)

var active_control_block: ControlBlock:
	get:
		return (
			block_assembly.active_control_block
			if block_assembly != null
			else null
		)


func _init() -> void:
	block_assembly = BlockAssembly.new(self)
	block_assembly.owner_id = _owner_id


func refresh_functional_state(
	preferred_control: ControlBlock = active_control_block
) -> void:
	workshop_blocks.clear()
	for block: Block in functional_blocks:
		if block is WorkshopBlock:
			workshop_blocks.append(block as WorkshopBlock)
	block_assembly.rebuild(functional_blocks, preferred_control)


func is_vehicle_workshop() -> bool:
	return not workshop_blocks.is_empty()


func get_workshop_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for workshop: WorkshopBlock in workshop_blocks:
		for cell: Vector2i in workshop.get_occupied_cells():
			if not result.has(cell):
				result.append(cell)
	return result


func get_docked_vehicles() -> Array[Vehicle]:
	var result: Array[Vehicle] = []
	for workshop: WorkshopBlock in workshop_blocks:
		var vehicle := workshop.get_docked_vehicle()
		if is_instance_valid(vehicle) and not result.has(vehicle):
			result.append(vehicle)
	return result


func get_workshop_for_vehicle(target: Vehicle) -> WorkshopBlock:
	if not is_instance_valid(target) or target.owner_id != owner_id:
		return null
	for workshop: WorkshopBlock in workshop_blocks:
		if workshop.get_docked_vehicle() == target:
			return workshop
	return null


func get_workshop_for_block(target: WorkshopBlock) -> WorkshopBlock:
	return target if workshop_blocks.has(target) else null


func update_functional_systems() -> void:
	block_assembly.update_stationary_power()


func has_control_block(control_block: ControlBlock) -> bool:
	return block_assembly.has_control_block(control_block)


func is_active_control_block(control_block: ControlBlock) -> bool:
	return block_assembly.is_active_control_block(control_block)


func set_active_control_block(control_block: ControlBlock) -> bool:
	return block_assembly.set_active_control_block(control_block)


func get_drive_input() -> Dictionary:
	return block_assembly.get_drive_input()


func has_aim_command() -> bool:
	return block_assembly.has_aim_command()


func get_aim_target() -> Vector2:
	return block_assembly.get_aim_target()


func get_fire_command() -> bool:
	return block_assembly.get_fire_command()


func get_construction_storages() -> Array[ItemStorage]:
	return block_assembly.get_construction_storages()


func can_supply_item(
	requester: Block,
	item_name: String,
	amount: int
) -> bool:
	return block_assembly.can_supply_item(requester, item_name, amount)


func supply_item(
	requester: Block,
	item_name: String,
	amount: int
) -> bool:
	return block_assembly.supply_item(requester, item_name, amount)


func can_receive_item(
	requester: Block,
	item_name: String,
	amount: int = 1
) -> bool:
	return block_assembly.can_receive_item(requester, item_name, amount)


func receive_item(
	requester: Block,
	item_name: String,
	amount: int
) -> int:
	return block_assembly.receive_item(requester, item_name, amount)


func can_supply_liquids(
	requester: Block,
	liquid_requests: Dictionary
) -> bool:
	return block_assembly.can_supply_liquids(
		requester,
		liquid_requests
	)


func supply_liquids(
	requester: Block,
	liquid_requests: Dictionary
) -> bool:
	return block_assembly.supply_liquids(requester, liquid_requests)


func receive_liquid(
	requester: Block,
	liquid_name: String,
	amount: float
) -> float:
	return block_assembly.receive_liquid(
		requester,
		liquid_name,
		amount
	)


func get_total_mass() -> float:
	if world_block_layer == null:
		return 0.0
	var result := 0.0
	for anchor: Vector2i in block_anchors:
		var state := world_block_layer.get_block_state(anchor)
		if state.is_empty():
			continue
		var block_id := int(state["block_id"])
		var base_size := BlockDB.get_size(block_id)
		var stored_size: Vector2i = state.get("size", base_size)
		var base_units := maxi(base_size.x * base_size.y, 1)
		var stored_units := maxi(stored_size.x * stored_size.y, 1)
		result += (
			float(BlockDB.get_block(block_id).get("mass", 0.0))
			* float(stored_units)
			/ float(base_units)
		)
	return result


func distance_to_world_point(world_position: Vector2) -> float:
	if world_block_layer == null or occupied_cells.is_empty():
		return INF
	var nearest := INF
	for cell: Vector2i in occupied_cells:
		nearest = minf(
			nearest,
			world_block_layer.to_global(
				world_block_layer.map_to_local(cell)
			).distance_to(world_position)
		)
	return nearest
