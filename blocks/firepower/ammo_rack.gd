extends Ammorack

const HITPOINT:float = 100
const WEIGHT:float = 500
const BLOCK_NAME:String = 'ammo rack'
const SIZE:= Vector2(1, 1)
const TYPE:= "Firepower"
const AMMO_CAPACITY:float = 50.0
var icons:Dictionary = {"normal":"res://assets/icons/ammo_icon.png","selected":"res://assets/icons/ammo_icon_n.png"}

var description := ""

func _init():
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	type = TYPE
	ammo_storage = AMMO_CAPACITY
	ammo_storage_cap = AMMO_CAPACITY
	linear_damp = 5.0
	angular_damp = 1.0
