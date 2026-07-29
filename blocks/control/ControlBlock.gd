class_name ControlBlock
extends Block

func has_information_panel() -> bool:
	return true

func get_drive_command() -> Dictionary:
	return {
		"move": 0.0,
		"pivot": 0.0,
	}

func has_aim_command() -> bool:
	return false

func get_aim_target() -> Vector2:
	return global_position + Vector2.UP.rotated(global_rotation) * Globals.TILE_SIZE

func get_fire_command() -> bool:
	return false
