extends Block

const HITPOINT:int = 100
const WEIGHT:float = 200
const BLOCK_NAME:String = 'ammo rack'
const SIZE:= Vector2(1, 1)
var ammo_capacity:float = 50.0

func init():
	mass = WEIGHT
	current_hp = HITPOINT

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
