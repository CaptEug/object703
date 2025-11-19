class_name Fueltank
extends Cargo

var fuel_storage: int = 0 
var current_fuel_pack: float = 0.0 
var fuel_pack_capacity: float = 10.0 

func use_fuel(power: float, delta: float) -> bool:
	# 如果没有燃料了，返回false
	if fuel_storage <= 0 and current_fuel_pack <= 0:
		return false
	
	# 如果当前油包用完了，申请新油包
	if current_fuel_pack <= 0:
		if fuel_storage > 0:
			fuel_storage -= 1
			current_fuel_pack = fuel_pack_capacity
		else:
			return false
	
	# 使用当前油包
	var fuel_needed = power * delta
	if fuel_needed <= current_fuel_pack:
		current_fuel_pack -= fuel_needed
		return true
	else:
		# 当前油包不够用，用完当前油包并递归调用
		current_fuel_pack = 0
		return use_fuel(power - (current_fuel_pack / delta), delta)

# 添加燃料包
func add_fuel_packs(count: int) -> void:
	fuel_storage += count

# 获取总剩余燃料量
func get_total_fuel() -> float:
	return fuel_storage * fuel_pack_capacity + current_fuel_pack
