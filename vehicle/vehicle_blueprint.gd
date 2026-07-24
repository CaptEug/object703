class_name VehicleBlueprint
extends RefCounted

const VERSION := 1
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

	var block_records: Array = []
	for block in vehicle.blocks:
		var block_id := BlockDB.get_id_for_scene(block.scene_file_path)
		if block_id < 0:
			return _error("Unregistered block: %s" % block.block_name)
		block_records.append([
			block_id,
			block.origin_cell.x,
			block.origin_cell.y,
			block.rotation_index,
		])
	block_records.sort_custom(_sort_block_records)

	var shafts := _encode_cells(vehicle.power_system.shaft_grid.keys())
	var pipes := _encode_cells(vehicle.fluid_system.pipe_grid.keys())
	var tubes := _encode_cells(vehicle.supply_system.tube_grid.keys())

	var directory_result := ensure_directory()
	if not directory_result["ok"]:
		return directory_result

	var path := _get_path(clean_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _error("Could not open the blueprint file.")
	var text := "{\"vehicle_name\":%s,\"version\":%d,\"blocks\":%s,\"shafts\":%s,\"pipes\":%s,\"tubes\":%s}" % [
		JSON.stringify(clean_name),
		VERSION,
		JSON.stringify(block_records),
		JSON.stringify(shafts),
		JSON.stringify(pipes),
		JSON.stringify(tubes),
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
	parent.add_child(vehicle)
	vehicle.global_transform = transform

	for record in validated["data"]["blocks"]:
		var scene := BlockDB.get_scene(int(record[0]))
		var cell := Vector2i(int(record[1]), int(record[2]))
		if scene == null or not vehicle.place_block(scene, cell, int(record[3])):
			vehicle.queue_free()
			return _error("A block could not be placed at %s." % cell)

	for record in validated["data"]["shafts"]:
		var cell := Vector2i(int(record[0]), int(record[1]))
		if not vehicle.power_system.can_palce_shaft(cell):
			vehicle.queue_free()
			return _error("A shaft could not be placed at %s." % cell)
		vehicle.power_system.place_shaft(cell)

	for record in validated["data"]["pipes"]:
		var cell := Vector2i(int(record[0]), int(record[1]))
		if not vehicle.fluid_system.can_place_pipe(cell):
			vehicle.queue_free()
			return _error("A pipe could not be placed at %s." % cell)
		vehicle.fluid_system.place_pipe(cell)

	for record in validated["data"]["tubes"]:
		var cell := Vector2i(int(record[0]), int(record[1]))
		if not vehicle.supply_system.can_place_tube(cell):
			vehicle.queue_free()
			return _error("A tube could not be placed at %s." % cell)
		vehicle.supply_system.place_tube(cell)

	vehicle.update_vehicle()
	return {
		"ok": true,
		"name": validated["data"]["vehicle_name"],
		"vehicle": vehicle,
	}


static func _validate(data: Dictionary) -> Dictionary:
	if data.get("version", -1) != VERSION:
		return _error("Unsupported blueprint version.")
	if not data.get("vehicle_name", null) is String:
		return _error("The blueprint has no vehicle name.")

	for key in ["blocks", "shafts", "pipes", "tubes"]:
		if not data.get(key, null) is Array:
			return _error("Invalid blueprint field: %s" % key)

	var occupied := {}
	for record in data["blocks"]:
		if not _valid_integer_record(record, 4):
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
		block.origin_cell = Vector2i(int(record[1]), int(record[2]))
		block.rotation_index = rotation
		for cell in block.get_occupied_cells():
			if occupied.has(cell):
				block.free()
				return _error("Blueprint blocks overlap at %s." % cell)
			occupied[cell] = true
		block.free()

	for key in ["shafts", "pipes", "tubes"]:
		var seen := {}
		for record in data[key]:
			if not _valid_integer_record(record, 2):
				return _error("Invalid %s record." % key)
			var cell := Vector2i(int(record[0]), int(record[1]))
			if seen.has(cell) or not occupied.has(cell):
				return _error("Invalid or duplicate %s cell: %s" % [key, cell])
			seen[cell] = true

	return {"ok": true, "data": data}


static func _valid_integer_record(record, expected_size: int) -> bool:
	if not record is Array or record.size() != expected_size:
		return false
	for value in record:
		if not value is int and not value is float:
			return false
		if int(value) != value:
			return false
	return true


static func _encode_cells(cells: Array) -> Array:
	var records: Array = []
	for cell in cells:
		records.append([cell.x, cell.y])
	records.sort_custom(_sort_cell_records)
	return records


static func _sort_block_records(a: Array, b: Array) -> bool:
	if a[2] != b[2]:
		return a[2] < b[2]
	if a[1] != b[1]:
		return a[1] < b[1]
	return a[0] < b[0]


static func _sort_cell_records(a: Array, b: Array) -> bool:
	if a[1] != b[1]:
		return a[1] < b[1]
	return a[0] < b[0]


static func _get_path(vehicle_name: String) -> String:
	return DIRECTORY + vehicle_name.validate_filename() + ".json"


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
