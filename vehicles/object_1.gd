extends Vehicle

var total_power:int
var total_weight:int

# Called when the node enters the scene tree for the first time.
func _ready():
	$Track_left.state = ''
	$Track_right.state = ''


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if Input.is_action_pressed("FORWARD"):  # Typically W key
		$Track_left.state = 'forward'
		$Track_right.state = 'forward'
	elif Input.is_action_pressed("BACKWARD"):  # Typically S key
		$Track_left.state = 'backward'
		$Track_right.state = 'backward'
	else:
		$Track_left.state = ''
		$Track_right.state = ''
	pass
