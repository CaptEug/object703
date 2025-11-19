extends Camera2D

var zoom_speed: float = 0.1
var zoom_min: float = 0.5
var zoom_max: float = 3.0
var move_speed: float = 500
var rotation_speed: float = 5.0
var focused: bool = false
var target_pos: Vector2 = Vector2.ZERO
var target_rot: float = 0.0
var move_tween: Tween = null

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
	sync_rotation_with(delta, target_rot)
	
	# 只在目标位置变化时更新 tween
	if global_position.distance_to(target_pos) > 1.0:
		update_camera_tween()

func update_camera_tween():
	# 如果已经有活跃的 tween，先停止它
	if move_tween and move_tween.is_valid():
		move_tween.kill()
	
	# 创建新的 tween
	move_tween = get_tree().create_tween()
	move_tween.tween_property(self, "global_position", target_pos, 0.5)

func focus_on_vehicle(vehicle: Vehicle):
	if not vehicle:
		return
		
	target_pos = vehicle.get_global_mass_center()
	
	if vehicle.control.get_method() == "manual_control":
		if Input.is_action_pressed("AIMING"):
			var viewport_center = Vector2(get_viewport().size / 2)
			var mouse_pos = get_viewport().get_mouse_position()
			var mouse_offset = mouse_pos - viewport_center
			target_pos += mouse_offset

	focused = true
	update_camera_tween()

func sync_rotation_to_vehicle(vehicle: Vehicle):
	if not vehicle:
		return
		
	for pos in vehicle.grid.keys():
		var block = vehicle.grid[pos]
		var vehicle_rotation = block.global_rotation - deg_to_rad(block.base_rotation_degree)
		target_rot = vehicle_rotation
		break

func sync_rotation_with(delta, target_rotation: float) -> void:
	var angle_diff = wrapf(target_rotation - global_rotation, -PI, PI)
	global_rotation += angle_diff * rotation_speed * delta

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
		input = input.normalized().rotated(target_rot)
		target_pos += input * move_speed * delta
		# 手动移动时取消聚焦状态
		focused = false

func get_rotation_angle(dir: String) -> float:
	match dir:
		"left":    return PI/2
		"up":      return 0
		"right":   return -PI/2
		"down":    return PI
		_:         return 0
