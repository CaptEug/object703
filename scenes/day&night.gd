extends CanvasModulate

@export var cycle_duration := 600.0
@export var day_color := Color(1, 1, 1)
@export var night_color := Color(0.3, 0.3, 0.3)
var time := 200.0
@onready var HUD := get_tree().current_scene.find_child("CanvasLayer").find_child("Hud")

func _process(delta):
	time = fmod(time + delta, cycle_duration)
	var t = time / cycle_duration
	 # Shift the sine phase so 0.25 = sunrise, 0.5 = noon, 0.75 = sunset
	var brightness = clamp((sin(t * TAU - TAU/4) + 1.0) / 2.0, 0.0, 1.0)
	color = day_color.lerp(night_color, 1.0 - brightness)
	
	if HUD:
		HUD.time = get_clock_string()

func get_clock_string() -> String:
	var total_minutes = (time / cycle_duration) * 24.0 * 60.0
	var hour = int(total_minutes / 60.0) % 24
	var minute = int(total_minutes) % 60
	return "%02d:%02d" % [hour, minute]
