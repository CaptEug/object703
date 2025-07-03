class_name Powerpack
extends Block

# 抽象属性 - 需要在子类中定义
var power: float
var max_power: float
var icons:Dictionary = {"normal":"res://assets/icons/engine_icon.png","selected":"res://assets/icons/engine_icon_n.png"}


func _ready():
	super._ready()
	power = max_power
	pass
