extends GPUParticles2D

@export var smokecolor_gradient:Gradient
var engine:Powerpack
var one:= 1.0

func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if get_parent().starting:
		emitting = true
		one -= delta/2
		var smoke_color = smokecolor_gradient.sample(max(0.0, one))
		modulate = smoke_color
		amount_ratio = max(0.1, one)
	else:
		emitting = get_parent().functioning and get_parent().on
		update_color()
		update_number()
	
	if not get_parent().on:
		one = 1.0


func get_engine_power_rate() -> float:
	engine = get_parent() as Powerpack
	
	var engine_power_rate = engine.power/engine.max_power
	
	return engine_power_rate


func update_color():
	var ratio = get_engine_power_rate()
	var smoke_color = smokecolor_gradient.sample(clamp(ratio, 0.0, 1.0))
	modulate = smoke_color


func update_number():
	var ratio = get_engine_power_rate()
	amount_ratio = clamp(ratio, 0.1, 1.0)
