class_name Powerpack
extends Block

# 发动机属性
var power: float = 0
var max_power: float
var inputs:Dictionary[String, float] # per second
var solid_fuel:Dictionary[String, float]
var power_change_rate: float
var target_power: float
var state = {"move": false, "rotate": false}
var on:bool = false
var starting:bool = false

# 动力分配比例
var move_power_ratio: float = 1.0  # 移动动力比例
var rotate_power_ratio: float = 0.3  # 旋转动力比例 (30%)

var track_power_target = {}
var connected_fueltanks:Array[LiquidTank] = []
var connected_cargos:Array[Cargo] = []

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
		on = false
		power = 0
	
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

func load_solid_fuel():
	for item_id in inputs:
		if ItemDB.get_item(item_id)["tag"] == "material":
			for cargo in find_all_connected_cargo():
				if cargo.check_amount(item_id) > 0:
					cargo.take_item(item_id, 1)
					if not solid_fuel.has(item_id):
						solid_fuel[item_id] = ItemDB.get_item(item_id)["weight"]
					else:
						solid_fuel[item_id] += ItemDB.get_item(item_id)["weight"]

func fuel_reduction(delta):
	for item_id in inputs:
		var amount_needed = inputs[item_id] * (power/max_power) * delta
		if ItemDB.get_item(item_id)["tag"] == "material":
			while solid_fuel[item_id] < amount_needed:
				load_solid_fuel()
			solid_fuel[item_id] -= amount_needed
		elif ItemDB.get_item(item_id)["tag"] == "fuel":
			var mass_needed = inputs[item_id] * (power/max_power) * delta
			for tank in find_all_connected_fueltank():
				if tank.stored_liquid == item_id:
					if tank.stored_amount >= mass_needed:
						tank.take_liquid(item_id, mass_needed)
						mass_needed = 0
					else:
						tank.take_liquid(item_id, tank.stored_amount)
						mass_needed -= tank.stored_amount
					if mass_needed == 0:
						break
				
		#if parent_vehicle and connected_fueltanks.size() > 0:
		#var remaining_power = power * (fuel_consumption/max_power)
		#for tank in connected_fueltanks:
			#if tank is Fueltank and tank.get_total_fuel() > 0:
				#if tank.use_fuel(remaining_power , delta):
					#return
				#else:
					#remaining_power -= tank.get_total_fuel()

# 外部接口 - 调整分配比例（可用于不同驾驶模式）

func find_all_connected_fueltank():
	connected_fueltanks.clear()
	for block in get_all_connected_blocks():
		if block is LiquidTank:
			connected_fueltanks.append(block)
	return connected_fueltanks

func find_all_connected_cargo():
	connected_cargos.clear()
	for block in get_all_connected_blocks():
		if block is Cargo:
			connected_cargos.append(block)
	return connected_cargos

func has_fuel() -> bool:
	for item_id in inputs:
		var total_mass:float
		if ItemDB.get_item(item_id)["tag"] == "material":
			var mass_per_unit:float = ItemDB.get_item(item_id)["weight"]
			for cargo in find_all_connected_cargo():
				total_mass += cargo.check_amount(item_id) * mass_per_unit
		elif ItemDB.get_item(item_id)["tag"] == "fuel":
			for tank in find_all_connected_fueltank():
				if tank.stored_liquid == item_id:
					total_mass += tank.stored_amount
		if total_mass < inputs[item_id]:
			return false
	return true
