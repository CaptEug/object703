class_name BuildingSave
extends RefCounted

const VERSION := 0
const FILE_NAME := "buildings.json"


static func save_file(
	world_blocks: WorldBlockLayer,
	world_folder: String
) -> Dictionary:
	if not is_instance_valid(world_blocks):
		return _error("World block layer is unavailable.")
	var file := FileAccess.open(
		world_folder + FILE_NAME,
		FileAccess.WRITE
	)
	if file == null:
		return _error("Could not open buildings.json for writing.")
	file.store_string(JSON.stringify({
		"version": VERSION,
		"buildings": world_blocks.get_constructed_save_data(),
	}))
	file.close()
	return {"ok": true}


static func load_file(
	world_blocks: WorldBlockLayer,
	world_folder: String
) -> Dictionary:
	if not is_instance_valid(world_blocks):
		return _error("World block layer is unavailable.")
	var file := FileAccess.open(
		world_folder + FILE_NAME,
		FileAccess.READ
	)
	if file == null:
		return _error("Could not open buildings.json.")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return _error("buildings.json is not valid JSON data.")
	var data := parsed as Dictionary
	if int(data.get("version", -1)) != VERSION:
		return _error("Unsupported buildings.json version.")
	var records: Variant = data.get("buildings")
	if not records is Array:
		return _error("Invalid buildings field.")

	world_blocks.begin_bulk_edit()
	world_blocks.restore_constructed_save_data(records as Array)
	world_blocks.end_bulk_edit()
	return {
		"ok": true,
		"count": (records as Array).size(),
	}


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
