extends Track

const HITPOINT:float = 300
const WEIGHT:float = 500.0
const BLOCK_NAME:String = 'rusty track'
const TYPE:= "Mobility"
const SIZE:= Vector2(1, 1)
const FRICTION:float = 5.0
const MAX_FORCE:float = 1000.0
const COST:= [
	{"scrap": 6}
	]

var description := ""
var outline_tex := preload("res://assets/outlines/track_outline.png")

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	friction = FRICTION
	max_force = MAX_FORCE
	mask_up_path = "res://assets/masks/track_mask_up.png"
	mask_down_path = "res://assets/masks/track_mask_down.png"
	mask_single_path = "res://assets/masks/track_mask_single.png"
