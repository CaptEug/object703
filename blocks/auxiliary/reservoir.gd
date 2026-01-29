extends LiquidTank

const HITPOINT:float = 2000
const WEIGHT:float = 1000
const BLOCK_NAME:String = 'reservoir'
const TYPE:= "Auxilliary"
const SIZE:= Vector2(2, 2)
const ACCEPT:Array[String] = ["ALL"]
const CAPACITY:= 5000.0

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
