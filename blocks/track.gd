extends Block

const HITPOINT:int = 100
const WEIGHT:int = 1
var state:String
var force:int
var state_force: Array = ['', 0]
var lateral_damping_strength: float = 1000.0

func get_weight() -> float:
	return WEIGHT
# Called when the node enters the scene tree for the first time.
func _ready():
	set_state_force('idle', 0)
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func _physics_process(delta):
	track_move(delta)
		
func set_state_force(new_state: String, new_force: int):
	state = new_state
	force = new_force
	state_force = [new_state, new_force]

func _on_received_state_force_signal(state_force_signal):
	if state_force_signal is Array and state_force_signal.size() >= 2:
		set_state_force(state_force_signal[0], state_force_signal[1])
	elif state_force_signal is Dictionary:
		set_state_force(state_force_signal.get('state', ''), state_force_signal.get('force', 0))
		
func track_move(delta):
	var forward_dir = Vector2.UP.rotated(rotation)
	var velocity = linear_velocity
	var forward_speed = velocity.dot(forward_dir)
	var lateral_velocity = velocity - forward_dir * forward_speed
	var forward_velocity = forward_dir * forward_speed
	if lateral_velocity.length() > 2:
		apply_impulse(-lateral_velocity.normalized() * lateral_damping_strength * delta)
	elif lateral_velocity.length() >= 0 and lateral_velocity.length() < 2:
		linear_velocity = forward_velocity
	if state_force[0] == 'forward':
		apply_impulse(Vector2.UP.rotated(rotation) * state_force[1])
	elif state_force[0] == 'backward':
		apply_impulse(Vector2.DOWN.rotated(rotation) * state_force[1])
	else:
		if forward_velocity.length() > 1:
			apply_impulse(-forward_velocity.normalized() * lateral_damping_strength * delta)
		elif forward_velocity.length() >= 0 and forward_velocity.length() < 1:
			linear_velocity = Vector2(0,0)

		
	
	
