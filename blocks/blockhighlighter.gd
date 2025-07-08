extends Node2D

var block:Block

func _ready():
	block = get_parent() as Block

func _draw():
	var line_color = Color(1, 1, 0)
	var line_width: float = 2.0

	if block.highlighted:
		var collisionshape := block.find_child("CollisionShape2D") as CollisionShape2D
		if collisionshape and collisionshape.shape is RectangleShape2D:
			var extents = collisionshape.shape.extents + Vector2(line_width/2,line_width/2)
			var rect = Rect2(-extents, extents * 2)
			draw_rect(rect, line_color, false, line_width)
