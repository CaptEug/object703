extends GPUParticles2D

@export var smokecolor_gradient:Gradient


func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	emitting = get_parent().functioning
	update_color()
	update_number()


func get_engine_power_rate() -> float:
	var engine = get_parent() as Powerpack
	
	var engine_power_rate = engine.power/engine.max_power
	
	return engine_power_rate


func update_color():
	var ratio = get_engine_power_rate()
	var smoke_color = smokecolor_gradient.sample(clamp(ratio, 0.0, 1.0))
	modulate = smoke_color


func update_number():
	var ratio = get_engine_power_rate()
	amount_ratio = clamp(ratio, 0.2, 1.0)
