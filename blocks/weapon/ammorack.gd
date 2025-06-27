extends Block

const HITPOINT:int = 100
const WEIGHT:float = 500
const BLOCK_NAME:String = 'ammo rack'
const SIZE:= Vector2(1, 1)
var ammo_capacity:float = 50.0
var icons:Dictionary = {"normal":"res://assets/icons/ammo_icon.png","selected":"res://assets/icons/ammo_icon_n.png"}

func init():
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	linear_damp = 5.0
	angular_damp = 1.0



# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
