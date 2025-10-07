extends GPUParticles2D

@onready var canvas_mod = get_tree().current_scene.find_child("CanvasModulate") as CanvasModulate

func _ready():
	await get_tree().create_timer(lifetime).timeout
	queue_free()


func _process(delta):
	var c = canvas_mod.color
	# Compute per-channel inverse, avoid divide by zero
	var inv = Color(1.0 / max(c.r, 0.001), 1.0 / max(c.g, 0.001), 1.0 / max(c.b, 0.001))
	modulate = inv
