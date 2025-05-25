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
	if Input.is_action_pressed("FORWARD"):  # Typically W key
		state = 'forward'
	elif Input.is_action_pressed("BACKWARD"):  # Typically S key
		state = 'backward'
	else:
		state = ''
	pass

func _physics_process(delta):
	if state == 'forward':
		apply_impulse(Vector2.UP.rotated(rotation) * force)
	if state == 'backward':
		apply_impulse(Vector2.DOWN.rotated(rotation) * force)
