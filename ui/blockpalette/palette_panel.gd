extends Panel

var dragging := false
var last_mouse := Vector2.ZERO

@onready var palette := $Clipper/BlockPalette


func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = event.pressed
			last_mouse = event.position
	if event is InputEventMouseMotion and dragging:
		var delta = event.position - last_mouse
		last_mouse = event.position
		palette.position += delta
