class_name VehicleSave
extends RefCounted

const VERSION := 0
const FILE_NAME := "vehicles.json"
const VEHICLE_SCENE := preload("res://vehicle/Vehicle.tscn")


static func save_file(
	tree: SceneTree,
	world_folder: String
) -> Dictionary:
	if tree == null:
		return _error("Scene tree is unavailable.")
	var vehicle_records: Array = []
	for node: Node in tree.get_nodes_in_group("vehicles"):
		var vehicle := node as Vehicle
		if (
			not is_instance_valid(vehicle)
			or vehicle.is_queued_for_deletion()
		):
			continue
		vehicle_records.append(_capture_vehicle(vehicle))
	vehicle_records.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			var first_position: Array = first["position"]
			var second_position: Array = second["position"]
			if first_position[1] != second_position[1]:
				return first_position[1] < second_position[1]
			if first_position[0] != second_position[0]:
				return first_position[0] < second_position[0]
			return str(first["vehicle_name"]) < str(second["vehicle_name"])
	)

	var file := FileAccess.open(
		world_folder + FILE_NAME,
		FileAccess.WRITE
	)
	if file == null:
		return _error("Could not open vehicles.json for writing.")
	file.store_string(JSON.stringify({
		"version": VERSION,
		"vehicles": vehicle_records,
	}))
	file.close()
	return {"ok": true, "count": vehicle_records.size()}


static func load_file(
	parent: Node,
	world_folder: String
) -> Dictionary:
	if not is_instance_valid(parent):
		return _error("Vehicle parent is unavailable.")
	var file := FileAccess.open(
		world_folder + FILE_NAME,
		FileAccess.READ
	)
	if file == null:
		return _error("Could not open vehicles.json.")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return _error("vehicles.json is not valid JSON data.")
	var data := parsed as Dictionary
	if int(data.get("version", -1)) != VERSION:
		return _error("Unsupported vehicles.json version.")
	var records: Variant = data.get("vehicles")
	if not records is Array:
		return _error("Invalid vehicles field.")

	var loaded: Array[Vehicle] = []
	for value: Variant in records:
		if not value is Dictionary:
			_free_loaded(loaded)
			return _error("Invalid vehicle record.")
		var restored := _restore_vehicle(value as Dictionary, parent)
		if not restored["ok"]:
			_free_loaded(loaded)
			return restored
		loaded.append(restored["vehicle"] as Vehicle)
	return {
		"ok": true,
		"count": loaded.size(),
		"vehicles": loaded,
	}


static func _capture_vehicle(vehicle: Vehicle) -> Dictionary:
	vehicle.ensure_blueprint_from_blocks()
	vehicle.reconcile_blueprint_with_blocks()
	var sorted_blocks: Array[Block] = []
	for block: Block in vehicle.blocks:
		sorted_blocks.append(block)
	sorted_blocks.sort_custom(
		func(first: Block, second: Block) -> bool:
			if first.origin_cell.y != second.origin_cell.y:
				return first.origin_cell.y < second.origin_cell.y
			if first.origin_cell.x != second.origin_cell.x:
				return first.origin_cell.x < second.origin_cell.x
			return first.block_id < second.block_id
	)
	var block_records: Array = []
	for block: Block in sorted_blocks:
		block_records.append(_capture_block(block))

	var result := {
		"vehicle_name": vehicle.vehicle_name,
		"owner_name": String(vehicle.owner_id),
		"position": [
			vehicle.global_position.x,
			vehicle.global_position.y,
		],
		"rotation": vehicle.global_rotation,
		"linear_velocity": [
			vehicle.linear_velocity.x,
			vehicle.linear_velocity.y,
		],
		"angular_velocity": vehicle.angular_velocity,
		"sleeping": vehicle.sleeping,
		"blocks": block_records,
		"blueprint": vehicle.blueprint_blocks.duplicate(true),
	}
	if is_instance_valid(vehicle.active_control_block):
		var control_anchor := vehicle.active_control_block.origin_cell
		result["active_control"] = [control_anchor.x, control_anchor.y]
	return result


static func _capture_block(block: Block) -> Array:
	var health := (
		0
		if block.max_hp <= 0.0
		else clampi(
			roundi(block.hp / block.max_hp * 65535.0),
			0,
			65535
		)
	)
	var record: Array = [
		block.block_id,
		block.origin_cell.x,
		block.origin_cell.y,
		block.rotation_index,
		health,
	]
	var extra := {}
	if block.size != BlockDB.get_size(block.block_id):
		extra["size"] = [block.size.x, block.size.y]
	var state := block.get_save_state()
	if not state.is_empty():
		extra["state"] = state
	if not extra.is_empty():
		record.append(extra)
	return record


static func _restore_vehicle(
	record: Dictionary,
	parent: Node
) -> Dictionary:
	var position_value: Variant = record.get("position")
	var velocity_value: Variant = record.get("linear_velocity")
	var blocks_value: Variant = record.get("blocks")
	var blueprint_value: Variant = record.get("blueprint")
	if (
		not _is_vector_record(position_value)
		or not _is_vector_record(velocity_value)
		or not blocks_value is Array
		or not blueprint_value is Array
	):
		return _error("Invalid vehicle transform, blocks, or blueprint.")

	var vehicle := VEHICLE_SCENE.instantiate() as Vehicle
	if vehicle == null:
		return _error("Vehicle scene could not be created.")
	vehicle.freeze = true
	vehicle.vehicle_name = str(record.get("vehicle_name", "New Vehicle"))
	vehicle.owner_id = StringName(str(record.get("owner_name", "player")))
	parent.add_child(vehicle)
	vehicle.global_position = Vector2(
		float((position_value as Array)[0]),
		float((position_value as Array)[1])
	)
	vehicle.global_rotation = float(record.get("rotation", 0.0))

	for block_value: Variant in blocks_value:
		if not block_value is Array:
			vehicle.queue_free()
			return _error("Invalid vehicle block record.")
		var block_record := block_value as Array
		var restored := _restore_block(vehicle, block_record)
		if not restored["ok"]:
			vehicle.queue_free()
			return restored

	vehicle.update_vehicle()
	var blueprint_validation := VehicleBlueprint._validate({
		"vehicle_name": vehicle.vehicle_name,
		"version": VehicleBlueprint.VERSION,
		"blocks": (blueprint_value as Array).duplicate(true),
	})
	if not blueprint_validation["ok"]:
		vehicle.queue_free()
		return _error(
			"Invalid saved vehicle blueprint: %s"
			% blueprint_validation["error"]
		)
	vehicle.set_blueprint_records(
		blueprint_validation["data"]["blocks"]
	)

	var active_value: Variant = record.get("active_control")
	if _is_vector_record(active_value):
		var control := vehicle.get_block(Vector2i(
			int((active_value as Array)[0]),
			int((active_value as Array)[1])
		)) as ControlBlock
		if control != null:
			vehicle.set_active_control_block(control)

	vehicle.freeze = false
	vehicle.linear_velocity = Vector2(
		float((velocity_value as Array)[0]),
		float((velocity_value as Array)[1])
	)
	vehicle.angular_velocity = float(record.get("angular_velocity", 0.0))
	vehicle.sleeping = bool(record.get("sleeping", false))
	return {"ok": true, "vehicle": vehicle}


static func _restore_block(
	vehicle: Vehicle,
	record: Array
) -> Dictionary:
	if record.size() < 5 or record.size() > 6:
		return _error("Invalid vehicle block record size.")
	for index in 5:
		if not record[index] is int and not record[index] is float:
			return _error("Vehicle block record contains non-numeric fields.")
	var block_id := int(record[0])
	if (
		not BlockDB.has_block(block_id)
		or not BlockDB.can_place_on(block_id, BlockDB.HOST_VEHICLE)
	):
		return _error("Invalid vehicle block ID %d." % block_id)
	var scene := BlockDB.get_scene(block_id)
	if scene == null:
		return _error("Vehicle block %d has no scene." % block_id)
	var block_size := Vector2i.ZERO
	var state := {}
	if record.size() == 6:
		if not record[5] is Dictionary:
			return _error("Invalid vehicle block extra state.")
		var extra := record[5] as Dictionary
		var size_value: Variant = extra.get("size")
		if size_value != null:
			if not _is_vector_record(size_value):
				return _error("Invalid vehicle union size.")
			block_size = Vector2i(
				int((size_value as Array)[0]),
				int((size_value as Array)[1])
			)
			if block_size.x <= 0 or block_size.y <= 0:
				return _error("Invalid vehicle union dimensions.")
		var state_value: Variant = extra.get("state")
		if state_value is Dictionary:
			state = state_value as Dictionary

	var anchor := Vector2i(int(record[1]), int(record[2]))
	var rotation_index := int(record[3])
	if rotation_index < 0 or rotation_index > 3:
		return _error("Invalid vehicle block rotation.")
	if not vehicle.place_block(
		scene,
		anchor,
		rotation_index,
		block_size,
		false,
		false
	):
		return _error("Saved vehicle blocks overlap or cannot be placed.")
	var block := vehicle.get_block(anchor)
	if block == null or block.block_id != block_id:
		return _error("Restored vehicle block could not be resolved.")
	var health := clampi(int(record[4]), 0, 65535)
	block.hp = block.max_hp * float(health) / 65535.0
	block.apply_save_state(state)
	return {"ok": true}


static func _is_vector_record(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 2:
		return false
	for component: Variant in value as Array:
		if not component is int and not component is float:
			return false
	return true


static func _free_loaded(vehicles: Array[Vehicle]) -> void:
	for vehicle: Vehicle in vehicles:
		if is_instance_valid(vehicle):
			vehicle.queue_free()


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
