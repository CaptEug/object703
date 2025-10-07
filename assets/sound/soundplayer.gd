extends AudioStreamPlayer2D

var cam:Camera2D

func _ready():
	cam = get_tree().current_scene.find_child("Camera2D") as Camera2D


func _process(_delta):
	if cam:
		var zoom_factor = cam.zoom.x
		# map zoom to volume (closer zoom = louder, farther zoom = quieter)
		var t = clamp((cam.zoom_max - zoom_factor) / (cam.zoom_max - cam.zoom_min), 0.0, 1.0)
		volume_db = lerp(0.0, -12.0, t)  
		# 0 dB at min zoom, -12 dB at max zoom
