class_name VehicleManager
extends Node2D

# 块名到路径的映射（保留作为备选方案）
const BLOCK_PATHS := {
	"122mm D-52T cannon": "res://blocks/firepower/d_52t.tscn",
	"QF 6-pounder gun": "res://blocks/firepower/qf_6_pounder.tscn",
	"V-7": "res://blocks/mobility/v_7.tscn",
	"pike armor": "res://blocks/structual/pike_armor.tscn",
	"command cupola": "res://blocks/command/cupola.tscn",
	"rusty track": "res://blocks/mobility/rusty_track.tscn",
	"TurretRing1800mm": "res://blocks/structual/turret_ring_1800mm.tscn"
}

# 静态方法：通过块名获取场景路径
static func get_block_scene_path_by_name(block_name: String) -> String:
	# 首先尝试从映射中获取
	if BLOCK_PATHS.has(block_name):
		return BLOCK_PATHS[block_name]
	
	# 如果映射中没有，根据命名规则构建路径
	var type = get_block_type_by_name(block_name)
	
	# 将块名转换为文件名（小写，用下划线替换空格和连字符）
	var file_name = block_name.to_lower().replace(" ", "_").replace("-", "_")
	
	return "res://blocks/%s/%s.tscn" % [type, file_name]

# 根据块名判断类型
static func get_block_type_by_name(block_name: String) -> String:
	var name_lower = block_name.to_lower()
	
	# 结构块
	if "armor" in name_lower or "block" in name_lower or "pike" in name_lower:
		return "structual"
	# 移动性块
	elif "track" in name_lower or "wheel" in name_lower or "engine" in name_lower or "v_" in name_lower:
		return "mobility"
	# 火力块
	elif "cannon" in name_lower or "gun" in name_lower or "pounder" in name_lower or "d_52t" in name_lower:
		return "firepower"
	# 指挥块
	elif "command" in name_lower or "cupola" in name_lower or "driver" in name_lower:
		return "command"
	# 工业块
	elif "pump" in name_lower or "smelter" in name_lower or "forge" in name_lower:
		return "industrial"
	# 辅助块
	elif "ammo" in name_lower or "fuel" in name_lower or "turret" in name_lower or "drill" in name_lower or "cutter" in name_lower or "reservoir" in name_lower:
		return "auxiliary"
	# 默认结构块
	else:
		return "structual"

# 获取所有车辆的保存数据
func get_all_vehicles_data_for_save() -> Dictionary:
	var save_data := {}
	
	for child in get_children():
		if child is Vehicle:
			var vehicle: Vehicle = child
			save_data[vehicle.vehicle_name] = vehicle.get_save_data()
	
	return save_data

# 从保存数据创建车辆
func create_vehicle_from_save_data(vehicle_data: Dictionary) -> Vehicle:
	var vehicle = Vehicle.new()
	
	# 设置车辆位置
	if vehicle_data.has("position"):
		var pos_array = vehicle_data["position"]
		vehicle.global_position = Vector2(pos_array[0], pos_array[1])
	
	# 添加到场景
	add_child(vehicle)
	
	# 调用Vehicle的加载方法
	vehicle.load_from_save_data(vehicle_data)
	
	return vehicle

# 批量创建车辆
func create_vehicles_from_save_data(vehicles_data: Dictionary) -> void:
	for vehicle_name in vehicles_data:
		var vehicle_data = vehicles_data[vehicle_name]
		create_vehicle_from_save_data(vehicle_data)

# 保存游戏数据（包括车辆数据）
func save_game_data(world_folder: String, world_name: String):
	print("开始保存车辆数据...")
	
	# 获取所有车辆的保存数据
	var vehicles_data = get_all_vehicles_data_for_save()
	
	# 如果有车辆，保存到JSON文件
	if not vehicles_data.is_empty():
		var vehicles_file_path = world_folder + "%s.vehicles.json" % world_name
		var vehicles_file = FileAccess.open(vehicles_file_path, FileAccess.WRITE)
		if vehicles_file:
			vehicles_file.store_string(JSON.stringify(vehicles_data, "\t"))
			vehicles_file.close()
			print("车辆数据保存完成: ", vehicles_data.size(), "辆")
		else:
			push_error("无法保存车辆数据")
	else:
		print("没有车辆需要保存")

# 加载游戏数据（包括车辆数据）
func load_game_data(map_path: String):
	print("开始加载车辆数据...")
	
	# 首先清空现有车辆
	clear_all_vehicles()
	
	# 根据地图路径构造车辆数据文件路径
	var map_dir = map_path.get_base_dir()
	var map_name = map_path.get_file().get_basename()
	var vehicles_file_path = map_dir + "/" + map_name + ".vehicles.json"
	
	# 检查车辆数据文件是否存在
	if FileAccess.file_exists(vehicles_file_path):
		var vehicles_file = FileAccess.open(vehicles_file_path, FileAccess.READ)
		if vehicles_file:
			var json = JSON.new()
			var error = json.parse(vehicles_file.get_as_text())
			vehicles_file.close()
			
			if error == OK:
				var vehicles_data = json.data
				print("找到车辆数据文件，开始加载: ", vehicles_data.size(), "辆")
				create_vehicles_from_save_data(vehicles_data)
				print("车辆数据加载完成")
			else:
				push_error("解析车辆数据失败: ", json.get_error_message())
	else:
		print("未找到车辆数据文件")

# 清除所有车辆
func clear_all_vehicles() -> void:
	for child in get_children():
		if child is Vehicle:
			child.queue_free()
	print("所有车辆已清除")

# 删除指定车辆
func remove_vehicle(vehicle_name: String) -> bool:
	for child in get_children():
		if child is Vehicle and child.vehicle_name == vehicle_name:
			child.queue_free()
			print("车辆已删除: ", vehicle_name)
			return true
	return false

# 获取车辆信息
func get_vehicles_info() -> Array:
	var info = []
	for child in get_children():
		if child is Vehicle:
			var vehicle: Vehicle = child
			info.append({
				"name": vehicle.vehicle_name,
				"position": [vehicle.global_position.x, vehicle.global_position.y],
				"blocks": vehicle.blocks.size(),
				"destroyed": vehicle.destroyed
			})
	return info

# 检查指定名称的车辆是否存在
func has_vehicle(vehicle_name: String) -> bool:
	for child in get_children():
		if child is Vehicle and child.vehicle_name == vehicle_name:
			return true
	return false

# 获取指定车辆
func get_vehicle(vehicle_name: String) -> Vehicle:
	for child in get_children():
		if child is Vehicle and child.vehicle_name == vehicle_name:
			return child
	return null
