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
	var current_assembly := get_assembly()
	if current_assembly == null or not is_inside_tree():
		return false
	var constructor := get_tree().get_first_node_in_group(
		"building_constructor"
	) as BuildingConstructor
	if constructor != null and constructor.is_active():
		return false
	var editor := _get_vehicle_editor()
	if editor != null and editor.is_editing_vehicle():
		return false
	if current_assembly.host is Vehicle:
		var vehicle_panel := get_tree().get_first_node_in_group(
			"vehicle_panel"
		)
		return (
			vehicle_panel != null
			and vehicle_panel.has_method("is_vehicle_selected")
			and vehicle_panel.is_vehicle_selected(
				current_assembly.host
			)
		)
	if current_assembly.host is Building:
		var building_panel := get_tree().get_first_node_in_group(
			"building_panel"
		)
		return (
			building_panel != null
			and building_panel.has_method("is_building_selected")
			and building_panel.is_building_selected(
				current_assembly.host
			)
		)
	return true

func _get_vehicle_editor() -> VehicleEditor:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return null
	return current_scene.get_node_or_null("UI/VehicleEditor") as VehicleEditor
