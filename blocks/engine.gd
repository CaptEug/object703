extends Block

const HITPOINT:int = 100
const WEIGHT:float = 50
var block_name:String = 'engine'
var size:= Vector2(1, 1)
var power:int = 200

func init():
	mass = WEIGHT
	current_hp = HITPOINT
	linear_damp = 5.0
# Called when the node enters the scene tree for the first time.
func _ready():
	super._ready()
	add_to_group("engines")
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
