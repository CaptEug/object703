class_name Powerpack
extends Block

# 抽象属性 - 需要在子类中定义
var power: float = 0
var max_power: float
var rotating_power: float
var power_change_rate: float
var target_power: float
var state = {"move": false, "rotate": false}
var track_power_target = {}
var fuel_enough = false

func _ready():
	super._ready()
	# 连接到载具动力系统
	if parent_vehicle:
		parent_vehicle.powerpacks.append(self)

func _process(delta: float) -> void:
	if parent_vehicle != null:
		if parent_vehicle.get_current_fuel() > 0:
				fuel_enough = true
	if fuel_enough:
		speed(delta)
		fuel_reduction(delta)
	else:
		Power_reduction(delta)
	pass

func Power_increases(delta):
	if power < target_power:
		power = power + power_change_rate * delta 
	
	
	

func Power_reduction(delta):
	if power > 0:
		power = power - power_change_rate * delta
	if abs(power) < power_change_rate * 0.01:
		power = 0

func Target_power():
	if state["move"] == true:
		target_power = max_power
	else:
		if state["rotate"] == true:
			target_power = max_power * rotating_power
			if power > max_power * rotating_power:
				power  = max_power * rotating_power
		else:
			target_power = 0
	
func speed(delta):
	Target_power()
	if power < target_power:
		Power_increases(delta)
	else:
		Power_reduction(delta)

func caculate_most_move_power(forward_input, turn_input):
	if parent_vehicle != null:
		var track_power_move
		var track_power_rotat
		track_power_move = parent_vehicle.balanced_forces
		track_power_rotat = parent_vehicle.rotation_forces
		for track in track_power_move:
			if state["move"] != false:
				if state["rotate"] == false:
					track_power_target[track] = track_power_move[track] * power * forward_input
				else:
					track_power_target[track] = track_power_move[track] * power * (1 - rotating_power) * forward_input + track_power_rotat[track] * power * rotating_power * turn_input					
			else:
				if state["rotate"] != false:
					track_power_target[track] = track_power_rotat[track] * power * turn_input
				else:
					track_power_target[track] = 0
		
func fuel_reduction(delta):
	if parent_vehicle:
		var each_power = power/parent_vehicle.fueltanks.size()
		for tank:Fueltank in parent_vehicle.fueltanks:
			tank.use_fuel(each_power, delta)
		if parent_vehicle.get_current_fuel() == 0:
			fuel_enough = false
