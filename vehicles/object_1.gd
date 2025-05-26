extends Vehicle


# Called when the node enters the scene tree for the first time.
func _ready():
	super._ready()
	total_power = self.get_total_engine_power()
	self.set_total_track_liner_damp(2)
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	super._process(delta)
	$Track_left.set_state_force(move_state,total_power)
	$Track_right.set_state_force(move_state,total_power)
	pass
