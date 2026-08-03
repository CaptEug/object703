class_name GameScene
extends Node2D

const BUILDING_SAVE := preload("res://building/building_save.gd")
const VEHICLE_SAVE := preload("res://vehicle/vehicle_save.gd")

@onready var gamemap:GameMap = $Gamemap
@onready var gameUI:CanvasLayer = $UI
@onready var camera:Camera2D = $Camera2D
var world_name:String
var world_seed:String
var world_data:Dictionary


# In-Game Time Management
var game_time:= 200.0
const CYCLE_DURATION := Globals.CYCLE_DURATION


func _ready() -> void:
	GameState.current_gamescene = self
	if GameState.world_gen_data:
		# New world: generate
		gen_world()
	else:
		# Existing world, load it
		load_world()
	


func _process(delta: float) -> void:
	update_game_time(delta)
	

func update_game_time(delta):
	game_time = fmod(game_time + delta, CYCLE_DURATION)
	gamemap.canvas_modulate.time = game_time


func gen_world():
	world_name = GameState.world_gen_data["name"]
	world_seed = GameState.world_gen_data["seed"]
	GameState.world_gen_data.clear()
	gamemap.world_seed = world_seed
	gamemap.generate_world()
	save_world(GameState.world_path)


func save_world(dir: String) -> bool:
	var success := true
	var header := {
		"name": world_name,
		"seed": world_seed,
		"last_played": Time.get_unix_time_from_system(),
		"version": GameState.WORLD_VERSION,
	}
	success = _write_json(dir + "header.json", header) and success
	var data := {
		"gametime": game_time,
	}
	success = _write_json(dir + "world.json", data) and success
	success = gamemap.save_map(dir) and success

	var building_result := BUILDING_SAVE.save_file(
		gamemap.world_blocks,
		dir
	)
	if not building_result["ok"]:
		push_error(building_result["error"])
		success = false
	var vehicle_result := VEHICLE_SAVE.save_file(get_tree(), dir)
	if not vehicle_result["ok"]:
		push_error(vehicle_result["error"])
		success = false

	if success:
		print("World save complete")
	return success


func load_world():
	var path = GameState.world_path
	
	# --- load header (optional but recommended) ---
	var header := _read_json(path + "header.json")
	if header.is_empty():
		push_error("Failed to read header.json")
		return
	world_name = header["name"]
	world_seed = header["seed"]
	
	# --- load world data ---
	var data := _read_json(path + "world.json")
	if data.is_empty():
		push_error("Failed to read world.json")
		return
	world_data = data
	game_time = world_data.get("gametime", 0)
	
	# Version 0 uses separate authoritative terrain, building, and vehicle files.
	gamemap.world_seed = world_seed
	if not gamemap.load_map(path + GameMap.MAP_FILE_NAME):
		return
	var building_result := BUILDING_SAVE.load_file(
		gamemap.world_blocks,
		path
	)
	if not building_result["ok"]:
		push_error(building_result["error"])
		return
	var vehicle_result := VEHICLE_SAVE.load_file(gamemap, path)
	if not vehicle_result["ok"]:
		push_error(vehicle_result["error"])
		return
	
func _write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s." % path)
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var result = JSON.parse_string(text)
	if typeof(result) != TYPE_DICTIONARY:
		return {}
	return result
