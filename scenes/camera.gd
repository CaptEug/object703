extends Camera2D

var zoom_speed:float = 0.1
var zoom_min:float = 0.5
var zoom_max:float = 3.0
@onready var control_ui := get_tree().current_scene.find_child("CanvasLayer") as CanvasLayer

func _ready():
	pass

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom *= 1.0 + zoom_speed
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom *= 1.0 - zoom_speed

		# Clamp zoom to stay within limits
		zoom.x = clamp(zoom.x, zoom_min, zoom_max)
		zoom.y = clamp(zoom.y, zoom_min, zoom_max)

func _process(delta):
	focus_on_vehicle()

func focus_on_vehicle():
	var focus_vehicle:Vehicle
	for vehicle in get_tree().get_nodes_in_group("vehicles"):
		if vehicle.control.get_method() == "manual_control":
			focus_vehicle = vehicle
	if focus_vehicle:
		smooth_move_to(focus_vehicle.center_of_mass)

func smooth_move_to(target_position:Vector2):
	var tween = get_tree().create_tween()
	tween.tween_property(self, "global_position", target_position, 0.5)
