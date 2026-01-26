extends Block

const HITPOINT:float = 500
const WEIGHT:float = 500
const BLOCK_NAME:String = 'pike armor'
const TYPE:= "Structual"
const SIZE:= Vector2(1, 1)
const COST:= {"metal": 1}
const KINETIC_ABSORB:= 0.9
const EXPLOSIVE_ABSORB:= 0.5

var description := ""
var outline_tex := preload("res://assets/outlines/pike_outline.png")

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	cost = COST
	kinetic_absorb = KINETIC_ABSORB
	explosice_absorb = EXPLOSIVE_ABSORB
