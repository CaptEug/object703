extends CanvasModulate

@export var cycle_duration := 600.0
@export var day_color := Color(1, 1, 1)
@export var night_color := Color(0.3, 0.3, 0.3)
var time := 200.0

func _process(delta):
	var t = time / cycle_duration
	 # Shift the sine phase so 0.25 = sunrise, 0.5 = noon, 0.75 = sunset
	var brightness = clamp((sin(t * TAU - TAU/4) + 1.0) / 2.0, 0.0, 1.0)
	color = day_color.lerp(night_color, 1.0 - brightness)
