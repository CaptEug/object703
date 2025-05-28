extends Block

const HITPOINT:int = 200
const WEIGHT:float = 200
const FRACTION = 1.0
var block_name:String = 'track'
var size:= Vector2(1, 1)
var state_force: Array = ['idle', 0.0]
var force_direction := Vector2.ZERO
var max_force = 500

func init():
	mass = WEIGHT
	current_hp = HITPOINT
	linear_damp = FRACTION
	#linear_damp_mode = RigidBody2D.DAMP_MODE_COMBINE
# Called when the node enters the scene tree for the first time.
func _ready():
	super._ready()
<<<<<<< HEAD
=======
	linear_damp = FRACTION
>>>>>>> 4468ca1144843ba16ed5fdfd7f1bc5032f5966bc
	add_to_group('tracks')
	set_state_force('idle', 0.0)
	queue_redraw()
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	queue_redraw()
	pass

func _physics_process(delta):
	track_move(delta)
		
func set_state_force(new_state: String, force_value: float):
	state_force = [new_state, clamp(force_value, -max_force, max_force)]

func _on_received_state_force_signal(state_force_signal):
	if state_force_signal is Array and state_force_signal.size() >= 2:
		set_state_force(state_force_signal[0], state_force_signal[1])
	elif state_force_signal is Dictionary:
		set_state_force(state_force_signal.get('state', ''), state_force_signal.get('force', 0))
		
func track_move(delta):
	if state_force[0] == 'forward' or state_force[0] == 'backward':
		apply_impulse(Vector2.UP.rotated(rotation) * state_force[1])
		force_direction = Vector2.UP


func _draw():
	draw_line(Vector2.ZERO, force_direction * state_force[1] * 10, Color.RED, 2)
