class_name ConstructionMaterials
extends RefCounted


static func get_candidate_storages(
	target_vehicle: Vehicle,
	build_world_position: Vector2,
	range_pixels: float
) -> Array[ItemStorage]:
	var result: Array[ItemStorage] = []
	if not is_instance_valid(target_vehicle):
		return result

	_append_vehicle_storages(target_vehicle, result)
	var nearby_vehicles: Array[Vehicle] = []
	for node: Node in target_vehicle.get_tree().get_nodes_in_group("vehicles"):
		var candidate := node as Vehicle
		if (
			not is_instance_valid(candidate)
			or candidate == target_vehicle
			or candidate.owner_id != target_vehicle.owner_id
			or candidate.distance_to_world_point(build_world_position)
			> range_pixels
		):
			continue
		nearby_vehicles.append(candidate)

	nearby_vehicles.sort_custom(
		func(first: Vehicle, second: Vehicle) -> bool:
			return (
				first.distance_to_world_point(build_world_position)
				< second.distance_to_world_point(build_world_position)
			)
	)
	for candidate: Vehicle in nearby_vehicles:
		_append_vehicle_storages(candidate, result)
	return result


static func get_missing(
	cost: Dictionary,
	storages: Array[ItemStorage]
) -> Dictionary:
	var missing := {}
	for item_value: Variant in cost:
		var item_id := str(item_value)
		var required := maxi(0, int(cost[item_value]))
		var available := 0
		for storage: ItemStorage in storages:
			if is_instance_valid(storage):
				available += storage.get_item_count(item_id)
		if available < required:
			missing[item_id] = required - available
	return missing


static func consume(
	cost: Dictionary,
	storages: Array[ItemStorage]
) -> Dictionary:
	var missing := get_missing(cost, storages)
	if not missing.is_empty():
		return {
			"ok": false,
			"missing": missing,
			"withdrawals": [],
		}

	var withdrawals: Array[Dictionary] = []
	for item_value: Variant in cost:
		var item_id := str(item_value)
		var remaining := maxi(0, int(cost[item_value]))
		for storage: ItemStorage in storages:
			if remaining <= 0:
				break
			if not is_instance_valid(storage):
				continue
			var taken := storage.take_item(item_id, remaining)
			if taken <= 0:
				continue
			withdrawals.append({
				"storage": storage,
				"item_id": item_id,
				"amount": taken,
			})
			remaining -= taken
	return {
		"ok": true,
		"missing": {},
		"withdrawals": withdrawals,
	}


static func refund(withdrawals: Array) -> void:
	for value: Variant in withdrawals:
		var withdrawal := value as Dictionary
		var storage := withdrawal.get("storage") as ItemStorage
		if not is_instance_valid(storage):
			continue
		var item_id := str(withdrawal.get("item_id", ""))
		var amount := int(withdrawal.get("amount", 0))
		if item_id.is_empty() or amount <= 0:
			continue
		storage.items[item_id] = storage.get_item_count(item_id) + amount
		storage.contents_changed.emit()


static func format_cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for item_value: Variant in cost:
		var item_id := str(item_value)
		var amount := int(cost[item_value])
		if amount > 0:
			parts.append("%d %s" % [amount, ItemDB.get_display_name(item_id)])
	return ", ".join(parts)


static func _append_vehicle_storages(
	source_vehicle: Vehicle,
	result: Array[ItemStorage]
) -> void:
	for block: Block in source_vehicle.blocks:
		if block is ItemStorage:
			result.append(block as ItemStorage)
