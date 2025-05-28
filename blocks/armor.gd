extends Block

const HITPOINT:int = 500
const WEIGHT:float = 1000
var block_name:String = 'armor'
var size:= Vector2(1, 1)

func init():
	mass = WEIGHT
	current_hp = HITPOINT


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
