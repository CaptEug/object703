extends Block

const HITPOINT:int = 200
const WEIGHT:float = 1000
var block_name:String = 'engine'
var size:= Vector2(1, 1)
var power:int = 20000

func init():
	mass = WEIGHT
	current_hp = HITPOINT

# Called when the node enters the scene tree for the first time.
func _ready():
	super._ready()
	add_to_group("engines")
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
