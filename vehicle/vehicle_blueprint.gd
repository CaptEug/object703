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

	for block: Block in vehicle.blocks:
		if BlockDB.get_id_for_scene(block.scene_file_path) < 0:
			return _error("Unregistered block: %s" % block.block_name)
	vehicle.ensure_blueprint_from_blocks()
	vehicle.reconcile_blueprint_with_blocks()
	var normalized := normalize_records(vehicle.blueprint_blocks)
	var block_records: Array = normalized["records"]

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


static func build(
	data: Dictionary,
	parent: Node,
	vehicle_scene: PackedScene,
	transform: Transform2D
) -> Dictionary:
	var validated := _validate(data)
	if not validated["ok"]:
		return validated

	var vehicle := vehicle_scene.instantiate() as Vehicle
	if vehicle == null:
		return _error("The vehicle scene could not be created.")
	vehicle.vehicle_name = validated["data"]["vehicle_name"]
	parent.add_child(vehicle)
	vehicle.global_transform = transform
	vehicle.set_blueprint_records(validated["data"]["blocks"])
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
		var block_size := _get_record_size(record)
		if (
			block_size != Vector2i.ZERO
			and not block is ExpandableStorage
		):
			block.free()
			return _error("Only expandable containers can have a saved size.")
		if block_size != Vector2i.ZERO:
			block.size = block_size
		var filter_index := _get_filter_index(record)
		if filter_index >= 0:
			if not block is ItemStorage and not block is LiquidStorage:
				block.free()
				return _error("Only storage blocks can have an allowed-item list.")
			for item_id: Variant in record[filter_index]:
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

	var normalized_data := data.duplicate(true)
	normalized_data["blocks"] = normalize_records(data["blocks"])["records"]
	return {"ok": true, "data": normalized_data}


static func _valid_block_record(record) -> bool:
	if not record is Array or record.size() < 4 or record.size() > 7:
		return false
	for index in 4:
		var value: Variant = record[index]
		if not value is int and not value is float:
			return false
		if int(value) != value:
			return false
	match record.size():
		5:
			if not record[4] is Array:
				return false
		6, 7:
			for index in [4, 5]:
				var size_value: Variant = record[index]
				if (
					not size_value is int
					and not size_value is float
				):
					return false
				if int(size_value) != size_value or int(size_value) <= 0:
					return false
			if record.size() == 7 and not record[6] is Array:
				return false
	return true


static func _get_record_size(record: Array) -> Vector2i:
	if record.size() >= 6:
		return Vector2i(int(record[4]), int(record[5]))
	return Vector2i.ZERO


static func _get_filter_index(record: Array) -> int:
	if record.size() == 5:
		return 4
	if record.size() == 7:
		return 6
	return -1


static func _sort_block_records(a: Array, b: Array) -> bool:
	if a[2] != b[2]:
		return a[2] < b[2]
	if a[1] != b[1]:
		return a[1] < b[1]
	return a[0] < b[0]


static func capture_vehicle_blocks(vehicle: Vehicle) -> Array:
	var records: Array = []
	for block: Block in vehicle.blocks:
		var record := make_block_record(block)
		if not record.is_empty():
			records.append(record)
	records.sort_custom(_sort_block_records)
	return records


static func make_block_record(block: Block) -> Array:
	var block_id := BlockDB.get_id_for_scene(block.scene_file_path)
	if block_id < 0:
		return []
	var record: Array = [
		block_id,
		block.origin_cell.x,
		block.origin_cell.y,
		block.rotation_index,
	]
	if block is ExpandableStorage and block.size != Vector2i.ONE:
		record.append(block.size.x)
		record.append(block.size.y)
	if block is ItemStorage:
		var item_storage := block as ItemStorage
		if not item_storage.is_default_allowed_items():
			record.append(item_storage.allowed_items.duplicate())
	elif block is LiquidStorage:
		var liquid_storage := block as LiquidStorage
		if not liquid_storage.is_default_allowed_items():
			record.append(liquid_storage.allowed_items.duplicate())
	return record


static func normalize_records(records: Array) -> Dictionary:
	var result: Array = records.duplicate(true)
	if result.is_empty():
		return {
			"records": result,
			"offset": Vector2i.ZERO,
		}
	var minimum := Vector2i(int(result[0][1]), int(result[0][2]))
	for record: Array in result:
		minimum.x = mini(minimum.x, int(record[1]))
		minimum.y = mini(minimum.y, int(record[2]))
	for record: Array in result:
		record[1] = int(record[1]) - minimum.x
		record[2] = int(record[2]) - minimum.y
	result.sort_custom(_sort_block_records)
	return {
		"records": result,
		"offset": minimum,
	}


static func reconcile_records(records: Array, vehicle: Vehicle) -> Array:
	var result: Array = records.duplicate(true)
	for block: Block in vehicle.blocks:
		var matching_index := get_matching_record_index(result, block)
		if matching_index >= 0:
			result[matching_index] = make_block_record(block)
			continue
		var block_cells := {}
		for cell: Vector2i in block.get_occupied_cells():
			block_cells[cell] = true
		for index in range(result.size() - 1, -1, -1):
			for cell: Vector2i in get_record_cells(result[index]):
				if block_cells.has(cell):
					result.remove_at(index)
					break
		var actual_record := make_block_record(block)
		if not actual_record.is_empty():
			result.append(actual_record)
	result.sort_custom(_sort_block_records)
	return result


static func has_matching_record(records: Array, block: Block) -> bool:
	return get_matching_record_index(records, block) >= 0


static func get_matching_record_index(records: Array, block: Block) -> int:
	var index := 0
	for record: Array in records:
		if record_matches_block(record, block):
			return index
		index += 1
	return -1


static func record_matches_block(record: Array, block: Block) -> bool:
	return (
		BlockDB.get_id_for_scene(block.scene_file_path) == int(record[0])
		and block.origin_cell == Vector2i(int(record[1]), int(record[2]))
		and block.rotation_index == int(record[3])
		and block.size == get_record_base_size(record)
	)


static func get_matching_block(vehicle: Vehicle, record: Array) -> Block:
	var block := vehicle.get_block(Vector2i(int(record[1]), int(record[2])))
	if block != null and record_matches_block(record, block):
		return block
	return null


static func get_record_cells(record: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var block_size := get_record_base_size(record)
	var rotation := int(record[3])
	var rotated_size := (
		block_size
		if rotation % 2 == 0
		else Vector2i(block_size.y, block_size.x)
	)
	var origin := Vector2i(int(record[1]), int(record[2]))
	for x in rotated_size.x:
		for y in rotated_size.y:
			cells.append(origin + Vector2i(x, y))
	return cells


static func get_record_base_size(record: Array) -> Vector2i:
	var saved_size := _get_record_size(record)
	if saved_size != Vector2i.ZERO:
		return saved_size
	var scene := BlockDB.get_scene(int(record[0]))
	var block := scene.instantiate() as Block if scene != null else null
	if block == null:
		return Vector2i.ONE
	var result := block.size
	block.free()
	return result


static func get_record_filter(record: Array) -> Array:
	var filter_index := _get_filter_index(record)
	if filter_index < 0:
		return []
	return record[filter_index].duplicate()


static func apply_record_filter(record: Array, block: Block) -> void:
	var filter_index := _get_filter_index(record)
	if filter_index < 0:
		return
	if block is ItemStorage:
		(block as ItemStorage).set_allowed_items(record[filter_index])
	elif block is LiquidStorage:
		(block as LiquidStorage).set_allowed_items(record[filter_index])

static func _get_path(vehicle_name: String) -> String:
	return DIRECTORY + vehicle_name.validate_filename() + ".json"


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
