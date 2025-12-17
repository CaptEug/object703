class_name Powerpack
extends Block

# 发动机属性
var power: float = 0
var max_power: float
var power_change_rate: float
var target_power: float
var state = {"move": false, "rotate": false}
var on:bool = false
var starting:bool = false

# 动力分配比例
var move_power_ratio: float = 1.0  # 移动动力比例
var rotate_power_ratio: float = 0.3  # 旋转动力比例 (30%)

var track_power_target = {}
var connected_fueltank = []
var total_fuel = 0

func _ready():
	super._ready()
	if parent_vehicle:
		parent_vehicle.powerpacks.append(self)


func _process(delta: float) -> void:
	super._process(delta)
	if not functioning:
		power = 0
		return
	
	if has_fuel():
		update_power(delta)
		fuel_reduction(delta)
	else:
		power_reduction(delta)
	
	if parent_vehicle:
		if parent_vehicle.control.get_method() == "":
			on = false

func start():
	starting = true
	await get_tree().create_timer(2.0).timeout
	starting = false
	on = true

func update_power(delta):
	# 根据状态确定目标功率
	if state["move"] or state["rotate"]:
		if not on:
			start()
		else:
			target_power = max_power  # 只要有需求就满功率
	else:
		target_power = 0
	
	# 平滑调整到目标功率
	if power < target_power:
		power = min(power + power_change_rate * delta, target_power)
	elif power > target_power:
		power = max(power - power_change_rate * delta, target_power)

func power_reduction(delta):
	if power > 0:
		power = max(power - power_change_rate * delta, 0)

func calculate_power_distribution(forward_input, turn_input):
	if not parent_vehicle:
		return
	var track_power_move = parent_vehicle.balanced_forces
	var track_power_rotat = parent_vehicle.rotation_forces
	
	# 计算总可用功率
	var available_power = power
	
	# 根据输入和状态分配功率
	for track in track_power_move:
		var move_component = 0.0
		var rotate_component = 0.0
		
		# 移动功率分量
		if state["move"]:
			move_component = track_power_move[track] * available_power * move_power_ratio * forward_input
		
		# 旋转功率分量  
		if state["rotate"]:
			rotate_component = track_power_rotat[track] * available_power * rotate_power_ratio * turn_input
		
		# 总功率 = 移动功率 + 旋转功率
		track_power_target[track] = move_component + rotate_component
		
		# 限制单条履带最大功率（防止过载）
		track_power_target[track] = clamp(track_power_target[track], -available_power, available_power)

func fuel_reduction(delta):
	if parent_vehicle and connected_fueltank.size() > 0:
		var required_fuel = power * delta
		var fuel_per_tank = required_fuel / connected_fueltank.size()
		var remaining_fuel_needed = required_fuel
		for tank in connected_fueltank:
			if tank is Fueltank and remaining_fuel_needed > 0:
				if tank.use_fuel(remaining_fuel_needed, delta):
					remaining_fuel_needed = 0
				else:
					var tank_fuel = tank.get_total_fuel()
					if tank_fuel > 0:
						tank.use_fuel(tank_fuel, delta)
						remaining_fuel_needed -= tank_fuel

# 外部接口 - 设置状态
func set_movement_state(moving: bool, rotating: bool):
	state["move"] = moving
	state["rotate"] = rotating

# 外部接口 - 调整分配比例（可用于不同驾驶模式）
func set_power_ratios(move_ratio: float, rotate_ratio: float):
	move_power_ratio = clamp(move_ratio, 0.0, 1.0)
	rotate_power_ratio = clamp(rotate_ratio, 0.0, 1.0)

func find_all_connected_fueltank():
	connected_fueltank.clear()
	for block in get_all_connected_blocks():
		if block is Fueltank:
			connected_fueltank.append(block)
	return connected_fueltank

func has_fuel() -> bool:
	connected_fueltank.clear()
	find_all_connected_fueltank()
	total_fuel = 0
	for fueltank:Fueltank in connected_fueltank:
		total_fuel += fueltank.get_total_fuel()
	if total_fuel > 0:
		return true
	else:
		on = false
		return false
