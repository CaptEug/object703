extends Camera2D

var zoom_speed:float = 0.1
var zoom_min:float = 0.5
var zoom_max:float = 3.0
var move_speed:float = 500
var rotation_speed:float = 5.0
var focused:bool
var target_pos:= Vector2(0,0)
var target_rot:= 0.0
@onready var control_ui := get_tree().current_scene.find_child("CanvasLayer") as CanvasLayer

func _ready():
	pass

func _input(event: InputEvent) -> void:
	var target_zoom = zoom
	if event is InputEventMouseButton:
		if not get_viewport().gui_get_hovered_control():
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				target_zoom *= 1.0 + zoom_speed
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				target_zoom *= 1.0 - zoom_speed

			# Clamp zoom to stay within limits
			target_zoom.x = clamp(target_zoom.x, zoom_min, zoom_max)
			target_zoom.y = clamp(target_zoom.y, zoom_min, zoom_max)
			var tween = get_tree().create_tween()
			tween.tween_property(self, "zoom", target_zoom, 0.5)


func _process(delta):
	movement(delta)
	smooth_move_to(target_pos)
	sync_rotation_with(delta, target_rot)


func focus_on_vehicle(vehicle:Vehicle):
	target_pos = vehicle.center_of_mass
	
	if vehicle.control.get_method() == "manual_control":
		if Input.is_action_pressed("AIMING"):
			var viewport_center = Vector2(get_viewport().size / 2)
			var mouse_pos = get_viewport().get_mouse_position()
			var mouse_offset = mouse_pos - viewport_center
			target_pos += mouse_offset

	focused = true

func sync_rotation_to_vehicle(vehicle:Vehicle):
	var command_block = vehicle.commands[0]
	var vehicle_rotation = command_block.global_rotation - get_rotation_angle(command_block.rotation_to_parent)
	target_rot = vehicle_rotation


func sync_rotation_with(delta, target_rotation: float) -> void:
	var angle_diff = wrapf(target_rotation - global_rotation, -PI, PI)
	global_rotation += angle_diff * rotation_speed * delta


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


func get_rotation_angle(dir: String) -> float:
	match dir:
		"left":    return PI/2
		"up": return 0
		"right":  return -PI/2
		"down":  return PI
		_:       return 0
