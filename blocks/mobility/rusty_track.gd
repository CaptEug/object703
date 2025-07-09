extends Track

const HITPOINT:int = 200
const WEIGHT:float = 500.0
const BLOCK_NAME:String = 'rusty track'
const TYPE:= "Mobility"
const SIZE:= Vector2(1, 1)
const FRICTION:float = 5.0
const MAX_FORCE:float = 1000000.0

var description := ""
var OUTLINE_TEX := preload("res://assets/icons/track_outline.png")

func _init():
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	friction = FRICTION
	max_force = MAX_FORCE
	outline_tex = OUTLINE_TEX
	linear_damp = 5.0
	angular_damp = 1.0
