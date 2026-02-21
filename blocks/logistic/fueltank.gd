extends LiquidTank

const HITPOINT:float = 400
const WEIGHT:float = 200
const BLOCK_NAME:String = 'fueltank'
const TYPE:= "Auxilliary"
const SIZE:= Vector2(1, 1)
const ACCEPT:Array[String] = ["petroleum"]
const CAPACITY:= 500.0

var description := "存储燃料供发动机使用"

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	type = TYPE
	size = SIZE
	accept = ACCEPT
	capacity = CAPACITY

func _ready() -> void:
	super._ready()
	add_liquid("petroleum", 100.0)
