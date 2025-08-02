class_name Powerpack
extends Block

# 抽象属性 - 需要在子类中定义
var power: float = 0
var max_power: float
var rotating_power: float
var icons:Dictionary = {"normal":"res://assets/icons/engine_icon.png","selected":"res://assets/icons/engine_icon_n.png"}
var power_change_rate: float
var target_power: float
var state = {"move": false, "rotate": false}

func _ready():
	super._ready()
	# 连接到载具动力系统
	if parent_vehicle:
		parent_vehicle.powerpacks.append(self)

func _process(delta: float) -> void:
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
	elif state["rotate"] == true:
		target_power = max_power * rotating_power
	
