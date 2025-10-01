extends Block

const HITPOINT:float = 250
const WEIGHT:float = 500
const BLOCK_NAME:String = 'pike armor'
const TYPE:= "Structual"
const SIZE:= Vector2(1, 1)
const COST:= [
	{"metal": 1}
	]

var description := ""
var outline_tex := preload("res://assets/icons/pike_outline.png")

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
