extends Block

const HITPOINT:int = 100
const WEIGHT:int = 1
var state:String
var force:int = 10
# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	
	pass

func _physics_process(delta):
	if state == 'forward':
		apply_impulse(Vector2.UP.rotated(rotation) * force)
	if state == 'backward':
		apply_impulse(Vector2.DOWN.rotated(rotation) * force)
