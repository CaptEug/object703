class_name Powerpack
extends Block

# 抽象属性 - 需要在子类中定义
var hitpoint: int
var weight: float
var block_name: String
var size: Vector2
var power: int

func _ready():
	super._ready()
	pass

func init():
	mass = weight
	current_hp = hitpoint
	linear_damp = 5.0  # 默认阻尼值
