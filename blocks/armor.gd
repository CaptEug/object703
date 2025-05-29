extends Block

const HITPOINT:int = 500
const WEIGHT:float = 1000
const BLOCK_NAME:String = 'armor'
const SIZE:= Vector2(1, 1)

func init():
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
