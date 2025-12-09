extends GPUParticles2D

@export var color_initial_ramp = Gradient.new()

func _ready():
	process_material.color_initial_ramp = color_initial_ramp
	await get_tree().create_timer(lifetime).timeout
	queue_free()
