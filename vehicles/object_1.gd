extends Vehicle

var total_power:int
var total_weight:int

# Called when the node enters the scene tree for the first time.
func _ready():
	$Track_left.state = 'forward'
	$Track_right.state = 'backward'


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
