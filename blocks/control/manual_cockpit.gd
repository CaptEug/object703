extends ControlBlock

func get_drive_command() -> Dictionary:
	if not _can_accept_player_control():
		return super()
	var move := Input.get_axis("BACKWARD", "FORWARD")
	var pivot := Input.get_axis("PIVOT_LEFT", "PIVOT_RIGHT")
	return {
		"move": clampf(move, -1.0, 1.0),
		"pivot": clampf(pivot, -1.0, 1.0),
	}

func has_aim_command() -> bool:
	return _can_accept_player_control()

func get_aim_target() -> Vector2:
	return get_global_mouse_position()

func get_fire_command() -> bool:
	if not _can_accept_player_control():
		return false
	if get_viewport().gui_get_hovered_control() != null:
		return false
	var editor := _get_vehicle_editor()
	if editor != null and editor.is_fire_suppressed():
		return false
	return Input.is_action_pressed("FIRE_MAIN")

func _can_accept_player_control() -> bool:
	if vehicle == null or not is_inside_tree():
		return false
	var editor := _get_vehicle_editor()
	if editor == null:
		return true
	if editor.is_editing_vehicle():
		return false
	return editor.vehicle == vehicle

func _get_vehicle_editor() -> VehicleEditor:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return null
	return current_scene.get_node_or_null("UI/VehicleEditor") as VehicleEditor
