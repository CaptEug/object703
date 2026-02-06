class_name GameScene
extends Node2D

@onready var gamemap:GameMap = $Gamemap
@onready var gameUI:CanvasLayer = $UI
@onready var camera:Camera2D = $Camera2D
var world_name:String
var world_seed:String
var world_data:Dictionary


# In-Game Time Management
var game_time:= 200.0
const CYCLE_DURATION := 600.0


func _ready() -> void:
	GameState.current_gamescene = self
	load_world()

func _process(delta: float) -> void:
	update_game_time(delta)
	

func update_game_time(delta):
	game_time = fmod(game_time + delta, CYCLE_DURATION)
	gamemap.canvas_modulate.time = game_time

func save_world(dir:String):
	# HEADER
	var header := {
		"name": world_name,
		"seed": world_data.get("seed", ""),
		"last_played": Time.get_unix_time_from_system(),
		"version": 1  # 更新版本号以表示包含车辆数据
	}
	_write_json(dir + "header.json", header)
	
	# WORLD DATA - 包含车辆数据
	var data := {
		"gametime": game_time,
		"vehicles": gamemap.vehicles.get_all_vehicles_data_for_save(),  # 获取所有车辆数据
		"buildings": gamemap.save_buildings(),
		#"technology":,
	}
	_write_json(dir + "world.json", data)
	
	# TILEMAP
	gamemap.save_map(dir)
	
	print("世界保存完成，包含 %d 辆车辆" % data["vehicles"].size())

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
	
	# load tilemap
	gamemap.load_map(path + world_name + ".map")
	
	# 加载车辆数据（从world.json中）
	if world_data.has("vehicles") and world_data["vehicles"] is Dictionary:
		print("开始从world.json加载车辆数据...")
		var vehicles_data: Dictionary = world_data["vehicles"]
		if vehicles_data.size() > 0:
			# 清除现有车辆
			gamemap.vehicles.clear_all_vehicles()
			# 从保存数据创建车辆
			gamemap.vehicles.create_vehicles_from_save_data(vehicles_data)
			print("从world.json加载了 %d 辆车辆" % vehicles_data.size())
		else:
			print("world.json中没有车辆数据")
	else:
		print("world.json中没有车辆数据字段")
	
	# 加载建筑数据（如果需要，从world.json中）
	if world_data.has("buildings") and world_data["buildings"] is Array:
		print("开始从world.json加载建筑数据...")
		var buildings_data: Array = world_data["buildings"]
		if buildings_data.size() > 0 and gamemap.building and gamemap.building.has_method("load_from_save_data"):
			gamemap.building.load_from_save_data(buildings_data)
			print("从world.json加载了 %d 个建筑" % buildings_data.size())


func _write_json(path: String, data: Dictionary):
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	
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
