class_name VehicleBlueprint
extends RefCounted

const VERSION := 0
const DIRECTORY := "user://vehicle_blueprints/"


static func ensure_directory() -> Dictionary:
	var absolute_directory := ProjectSettings.globalize_path(DIRECTORY)
	var error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if error != OK and error != ERR_ALREADY_EXISTS:
		return _error("Could not create the blueprint folder.")
	return {"ok": true}


static func save(vehicle: Vehicle, vehicle_name: String) -> Dictionary:
	if not is_instance_valid(vehicle):
		return _error("There is no vehicle to save.")

	var clean_name := vehicle_name.strip_edges()
	if clean_name.is_empty():
		return _error("Enter a vehicle name.")
	vehicle.vehicle_name = clean_name

	var block_records: Array = []
	for block in vehicle.blocks:
		var block_id := BlockDB.get_id_for_scene(block.scene_file_path)
		if block_id < 0:
			return _error("Unregistered block: %s" % block.block_name)
		var record: Array = [
			block_id,
			block.origin_cell.x,
			block.origin_cell.y,
			block.rotation_index,
		]
		if block is ItemStorage:
			var item_storage := block as ItemStorage
			if not item_storage.is_default_allowed_items():
				record.append(item_storage.allowed_items.duplicate())
		elif block is LiquidStorage:
			var liquid_storage := block as LiquidStorage
			if not liquid_storage.is_default_allowed_items():
				record.append(liquid_storage.allowed_items.duplicate())
		block_records.append(record)
	block_records.sort_custom(_sort_block_records)

	var directory_result := ensure_directory()
	if not directory_result["ok"]:
		return directory_result

	var path := _get_path(clean_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _error("Could not open the blueprint file.")
	var text := "{\"vehicle_name\":%s,\"version\":%d,\"blocks\":%s}" % [
		JSON.stringify(clean_name),
		VERSION,
		JSON.stringify(block_records),
	]
	file.store_string(text)
	file.close()
	return {"ok": true, "name": clean_name, "path": path}


static func load_data(vehicle_name: String) -> Dictionary:
	var clean_name := vehicle_name.strip_edges()
	if clean_name.is_empty():
		return _error("Enter a vehicle name.")

	return load_path(_get_path(clean_name))


static func load_path(path: String) -> Dictionary:
	if not path.ends_with(".json"):
		return _error("Select a JSON blueprint file.")

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error("Could not open the selected blueprint.")
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()

	if not parsed is Dictionary:
		return _error("The blueprint is not valid JSON.")
	return _validate(parsed)


static func build(data: Dictionary, parent: Node, vehicle_scene: PackedScene, transform: Transform2D) -> Dictionary:
	var validated := _validate(data)
	if not validated["ok"]:
		return validated

	var vehicle := vehicle_scene.instantiate() as Vehicle
	if vehicle == null:
		return _error("The vehicle scene could not be created.")
	vehicle.vehicle_name = validated["data"]["vehicle_name"]
	parent.add_child(vehicle)
	vehicle.global_transform = transform

	for record in validated["data"]["blocks"]:
		var scene := BlockDB.get_scene(int(record[0]))
		var cell := Vector2i(int(record[1]), int(record[2]))
		if scene == null or not vehicle.place_block(scene, cell, int(record[3])):
			vehicle.queue_free()
			return _error("A block could not be placed at %s." % cell)
		if record.size() == 5:
			var placed_block := vehicle.get_block(cell)
			if placed_block is ItemStorage:
				(placed_block as ItemStorage).set_allowed_items(record[4])
			elif placed_block is LiquidStorage:
				(placed_block as LiquidStorage).set_allowed_items(record[4])

	vehicle.update_vehicle()
	return {
		"ok": true,
		"name": validated["data"]["vehicle_name"],
		"vehicle": vehicle,
	}


static func _validate(data: Dictionary) -> Dictionary:
	if int(data.get("version", -1)) != VERSION:
		return _error("Unsupported blueprint version.")
	if not data.get("vehicle_name", null) is String:
		return _error("The blueprint has no vehicle name.")

	if not data.get("blocks", null) is Array:
		return _error("Invalid blueprint field: blocks")

	var occupied := {}
	for record in data["blocks"]:
		if not _valid_block_record(record):
			return _error("Invalid block record.")
		var block_id := int(record[0])
		var rotation := int(record[3])
		if not BlockDB.has_block(block_id) or rotation < 0 or rotation > 3:
			return _error("Invalid block ID or rotation.")

		var scene := BlockDB.get_scene(block_id)
		var block: Block = null
		if scene:
			block = scene.instantiate() as Block
		if block == null:
			return _error("Block ID %d is not a Block scene." % block_id)
		if record.size() == 5:
			if not block is ItemStorage and not block is LiquidStorage:
				block.free()
				return _error("Only storage blocks can have an allowed-item list.")
			for item_id: Variant in record[4]:
				if not item_id is String:
					block.free()
					return _error("Allowed item IDs must be text.")
				var compatible := false
				if block is ItemStorage:
					compatible = (block as ItemStorage).is_item_compatible(item_id)
				else:
					compatible = (block as LiquidStorage).is_item_compatible(item_id)
				if not compatible:
					block.free()
					return _error("Item %s is incompatible with block ID %d." % [item_id, block_id])
		block.origin_cell = Vector2i(int(record[1]), int(record[2]))
		block.rotation_index = rotation
		for cell in block.get_occupied_cells():
			if occupied.has(cell):
				block.free()
				return _error("Blueprint blocks overlap at %s." % cell)
			occupied[cell] = true
		block.free()

	return {"ok": true, "data": data}


static func _valid_block_record(record) -> bool:
	if not record is Array or record.size() < 4 or record.size() > 5:
		return false
	for index in 4:
		var value: Variant = record[index]
		if not value is int and not value is float:
			return false
		if int(value) != value:
			return false
	if record.size() == 5 and not record[4] is Array:
		return false
	return true


static func _sort_block_records(a: Array, b: Array) -> bool:
	if a[2] != b[2]:
		return a[2] < b[2]
	if a[1] != b[1]:
		return a[1] < b[1]
	return a[0] < b[0]

static func _get_path(vehicle_name: String) -> String:
	return DIRECTORY + vehicle_name.validate_filename() + ".json"


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
