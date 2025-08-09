extends Camera2D

var zoom_speed:float = 0.1
var zoom_min:float = 0.5
var zoom_max:float = 3.0
var move_speed:float = 500
var focused:bool
var target_pos:= Vector2(0,0)
@onready var control_ui := get_tree().current_scene.find_child("CanvasLayer") as CanvasLayer

func _ready():
	pass

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if not get_viewport().gui_get_hovered_control():
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom *= 1.0 + zoom_speed
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom *= 1.0 - zoom_speed

			# Clamp zoom to stay within limits
			zoom.x = clamp(zoom.x, zoom_min, zoom_max)
			zoom.y = clamp(zoom.y, zoom_min, zoom_max)

func _process(delta):
	focus_on_vehicle()
	movement(delta)
	smooth_move_to(target_pos)

func focus_on_vehicle():
	var focus_vehicle:Vehicle
	for vehicle in get_tree().get_nodes_in_group("vehicles"):
		if vehicle.control.get_method() == "manual_control":
			focus_vehicle = vehicle
	if focus_vehicle:
		if Input.is_action_pressed("AIMING"):
			var viewport_center = Vector2(get_viewport().size / 2)
			var mouse_pos = get_viewport().get_mouse_position()
			var mouse_offset = mouse_pos - viewport_center
			target_pos = focus_vehicle.center_of_mass + mouse_offset
		else:
			target_pos = focus_vehicle.center_of_mass
		focused = true
	else:
		focused = false


func smooth_move_to(target_position:Vector2):
	var tween = get_tree().create_tween()
	tween.tween_property(self, "global_position", target_position, 0.5) #move to position in 0.5s

func movement(delta):
	var input = Vector2.ZERO

	if Input.is_action_pressed("CAM_MOVE_RIGHT"):
		input.x += 1
	if Input.is_action_pressed("CAM_MOVE_LEFT"):
		input.x -= 1
	if Input.is_action_pressed("CAM_MOVE_DOWN"):
		input.y += 1
	if Input.is_action_pressed("CAM_MOVE_UP"):
		input.y -= 1

	# Normalize to prevent diagonal speed boost
	if input.length() > 0:
		input = input.normalized()
	target_pos += input * move_speed * delta
