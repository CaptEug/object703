extends Block

const HITPOINT:int = 300
const WEIGHT:float = 1000
const BLOCK_NAME:String = 'command cupola'
const SIZE:= Vector2(1, 1)

func _init():
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	linear_damp = 5.0
	angular_damp = 1.0

# Called when the node enters the scene tree for the first time.
func _ready():
	super._ready()
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass
