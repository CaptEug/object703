class_name ConstructionSupport
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
	var nearby := _get_nearby_construction_storages(
		target_vehicle.get_tree(),
		build_world_position,
		range_pixels,
		target_vehicle.owner_id,
		target_vehicle
	)
	for storage: ItemStorage in nearby:
		if not result.has(storage):
			result.append(storage)
	return result


static func get_workshop_candidate_storages(
	target_vehicle: Vehicle,
	workshop_building: Building
) -> Array[ItemStorage]:
	var result: Array[ItemStorage] = []
	if is_instance_valid(target_vehicle):
		_append_vehicle_storages(target_vehicle, result)
	if workshop_building == null:
		return result
	for storage: ItemStorage in workshop_building.get_construction_storages():
		if is_instance_valid(storage) and not result.has(storage):
			result.append(storage)
	return result


static func get_world_candidate_storages(
	tree: SceneTree,
	build_world_position: Vector2,
	range_pixels: float,
	owner_id: StringName
) -> Array[ItemStorage]:
	return _get_nearby_construction_storages(
		tree,
		build_world_position,
		range_pixels,
		owner_id,
		null
	)


static func has_world_construction_support(
	tree: SceneTree,
	build_world_position: Vector2,
	range_pixels: float,
	owner_id: StringName
) -> bool:
	if tree == null:
		return false
	var maximum_distance := maxf(range_pixels, 0.0)
	for node: Node in tree.get_nodes_in_group("vehicles"):
		var vehicle := node as Vehicle
		if (
			is_instance_valid(vehicle)
			and vehicle.owner_id == owner_id
			and vehicle.distance_to_world_point(build_world_position)
			<= maximum_distance
		):
			return true
	for node: Node in tree.get_nodes_in_group("world_block_layers"):
		var world_layer := node as WorldBlockLayer
		if world_layer == null:
			continue
		for building: Building in world_layer.buildings:
			if (
				building.owner_id == owner_id
				and building.distance_to_world_point(
					build_world_position
				) <= maximum_distance
			):
				return true
	return false


static func get_missing(
	cost: Dictionary,
	storages: Array[ItemStorage]
) -> Dictionary:
	var missing := {}
	for item_value: Variant in cost:
		var item_name := str(item_value)
		var required := maxi(0, int(cost[item_value]))
		var available := 0
		for storage: ItemStorage in storages:
			if is_instance_valid(storage):
				available += storage.get_item_count(item_name)
		if available < required:
			missing[item_name] = required - available
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
		var item_name := str(item_value)
		var remaining := maxi(0, int(cost[item_value]))
		for storage: ItemStorage in storages:
			if remaining <= 0:
				break
			if not is_instance_valid(storage):
				continue
			var taken := storage.take_item(item_name, remaining)
			if taken <= 0:
				continue
			withdrawals.append({
				"storage": storage,
				"item_name": item_name,
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
		var item_name := str(withdrawal.get("item_name", ""))
		var amount := int(withdrawal.get("amount", 0))
		if item_name.is_empty() or amount <= 0:
			continue
		storage.items[item_name] = (
			storage.get_item_count(item_name) + amount
		)
		storage.contents_changed.emit()


static func format_cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for item_value: Variant in cost:
		var item_name := str(item_value)
		var amount := int(cost[item_value])
		if amount > 0:
			parts.append(
				"%d %s"
				% [amount, ItemDB.get_display_name(item_name)]
			)
	return ", ".join(parts)


static func _append_vehicle_storages(
	source_vehicle: Vehicle,
	result: Array[ItemStorage]
) -> void:
	for storage: ItemStorage in (
		source_vehicle.block_assembly.get_construction_storages()
	):
		if not result.has(storage):
			result.append(storage)


static func _get_nearby_construction_storages(
	tree: SceneTree,
	build_world_position: Vector2,
	range_pixels: float,
	owner_id: StringName,
	excluded_vehicle: Vehicle
) -> Array[ItemStorage]:
	var ranked: Array[Dictionary] = []
	var seen := {}
	var maximum_distance := maxf(range_pixels, 0.0)

	for node: Node in tree.get_nodes_in_group("vehicles"):
		var candidate := node as Vehicle
		if (
			not is_instance_valid(candidate)
			or candidate == excluded_vehicle
			or candidate.owner_id != owner_id
		):
			continue
		var source_distance := candidate.distance_to_world_point(
			build_world_position
		)
		if source_distance > maximum_distance:
			continue
		var vehicle_storages: Array[ItemStorage] = []
		_append_vehicle_storages(candidate, vehicle_storages)
		for storage: ItemStorage in vehicle_storages:
			_append_ranked_storage(
				storage,
				source_distance,
				ranked,
				seen
			)

	for node: Node in tree.get_nodes_in_group("world_block_layers"):
		var world_layer := node as WorldBlockLayer
		if world_layer == null:
			continue
		for building: Building in world_layer.buildings:
			if building.owner_id != owner_id:
				continue
			for storage: ItemStorage in building.get_construction_storages():
				var source_distance := storage.global_position.distance_to(
					build_world_position
				)
				if source_distance > maximum_distance:
					continue
				_append_ranked_storage(
					storage,
					source_distance,
					ranked,
					seen
				)

	ranked.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			var first_distance := float(first["distance"])
			var second_distance := float(second["distance"])
			if not is_equal_approx(first_distance, second_distance):
				return first_distance < second_distance
			return int(first["instance_id"]) < int(second["instance_id"])
	)
	var result: Array[ItemStorage] = []
	for entry: Dictionary in ranked:
		result.append(entry["storage"] as ItemStorage)
	return result


static func _append_ranked_storage(
	storage: ItemStorage,
	distance: float,
	ranked: Array[Dictionary],
	seen: Dictionary
) -> void:
	if not is_instance_valid(storage):
		return
	var instance_id := storage.get_instance_id()
	if seen.has(instance_id):
		return
	seen[instance_id] = true
	ranked.append({
		"storage": storage,
		"distance": distance,
		"instance_id": instance_id,
	})
