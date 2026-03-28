class_name Pipe
extends Block

@onready var sprite := $Sprite2D
@export var single : Texture2D
@export var end : Texture2D
@export var straight : Texture2D
@export var straight2 : Texture2D
@export var corner : Texture2D
@export var T : Texture2D
@export var cross : Texture2D


func get_bit_mask(cell: Vector2i, pipe_grid: Dictionary) -> int:
	var mask := 0
	if pipe_grid.has(cell + Vector2i.UP):
		mask |= 1
	if pipe_grid.has(cell + Vector2i.RIGHT):
		mask |= 2
	if pipe_grid.has(cell + Vector2i.DOWN):
		mask |= 4
	if pipe_grid.has(cell + Vector2i.LEFT):
		mask |= 8
	return mask


func update_sprite() -> void:
	match get_bit_mask(origin_cell, vehicle.power_system.pipe_grid):
		5:
			sprite.texture = straight   # vertical
			sprite.rotation = 0
		10:
			sprite.texture = straight
			sprite.rotation = PI / 2
		3:
			sprite.texture = corner
			sprite.rotation = 0
		6:
			sprite.texture = corner
			sprite.rotation = PI / 2
		12:
			sprite.texture = corner
			sprite.rotation = PI
		9:
			sprite.texture = corner
			sprite.rotation = 3 * PI / 2
		7:
			sprite.texture = T
			sprite.rotation = 0
		14:
			sprite.texture = T
			sprite.rotation = PI / 2
		13:
			sprite.texture = T
			sprite.rotation = PI
		11:
			sprite.texture = T
			sprite.rotation = 3 * PI / 2
		15:
			sprite.texture = cross
			sprite.rotation = 0
		1:
			sprite.texture = end
			sprite.rotation = 0
		2:
			sprite.texture = end
			sprite.rotation = PI / 2
		4:
			sprite.texture = end
			sprite.rotation = PI
		8:
			sprite.texture = end
			sprite.rotation = 3 * PI / 2
		_:
			sprite.texture = single
			sprite.rotation = 0
