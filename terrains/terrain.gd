class_name Terrain
extends Area2D

func _ready():
	add_to_group('terrains')
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	pass
	
func _on_body_entered(body: Node):
	if body is Vehicle:
		body.set_total_track_liner_damp(get_liner_damp())
	print(1)

# 当物体离开区域
func _on_body_exited(body: Node):
	if body is Vehicle:
		body.set_total_track_liner_damp(0.1)
	
func stop_liner_damp_():
	var liner_damp = get_liner_damp()
	return liner_damp

func get_liner_damp() -> float:
	return 0.0
