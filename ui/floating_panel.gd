class_name FloatingPanel
extends Panel

var dragging := false
var drag_offset := Vector2.ZERO

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				move_to_front()
				dragging = true
				drag_offset = get_global_mouse_position() - global_position
				accept_event() # prevent clicks from passing through
			else:
				dragging = false
	
	elif event is InputEventMouseMotion and dragging:
		global_position = get_global_mouse_position() - drag_offset
		# keep it inside the screen bounds
		var rect = get_viewport_rect()
		global_position = global_position.clamp(Vector2.ZERO, rect.size - size)


func any_overlap() -> bool:
	var HUD = get_tree().root.get_node("Main/UI") as CanvasLayer
	for p in HUD.get_children():
		if p is FloatingPanel and p != self:
			var r = Rect2(p.position, Vector2(32, 32))
			if r.intersects(Rect2(position, size)):
				return true
	return false
