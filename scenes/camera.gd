extends Camera2D

var zoom_speed:float = 0.1
var zoom_min:float = 0.5
var zoom_max:float = 3.0

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom *= 1.0 + zoom_speed
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom *= 1.0 - zoom_speed

		# Clamp zoom to stay within limits
		zoom.x = clamp(zoom.x, zoom_min, zoom_max)
		zoom.y = clamp(zoom.y, zoom_min, zoom_max)
