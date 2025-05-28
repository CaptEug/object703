extends Block

const HITPOINT:int = 300
const WEIGHT:float = 500
var block_name:String = 'command cupola'
var size:= Vector2(1, 1)

func init():
	mass = WEIGHT
	current_hp = HITPOINT

# Called when the node enters the scene tree for the first time.
func _ready():
	super._ready()
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
