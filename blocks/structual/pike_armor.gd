extends Block

const HITPOINT:float = 250
const WEIGHT:float = 500
const BLOCK_NAME:String = 'pike armor'
const TYPE:= "Structual"
const SIZE:= Vector2(1, 1)

var description := ""
var outline_tex := preload("res://assets/icons/pike_outline.png")

func _init():
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	linear_damp = 5.0
	angular_damp = 1.0
