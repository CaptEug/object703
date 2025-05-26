extends Node2D

@export var block_scenes:Dictionary

const GRID_SIZE:int = 16
var current_block_type:String
var ghost_block
var placed_blocks:={}  # Dictionary of Vector2i -> block instance

func create_ghost_block():
	if ghost_block:
		ghost_block.queue_free()
	ghost_block = block_scenes[current_block_type].instantiate()
	ghost_block.modulate = Color(1, 1, 1, 0.5)  # Transparent ghost
	ghost_block.set_physics_process(false)
	add_child(ghost_block)

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func update_ghost_position():
	var mouse_pos = get_global_mouse_position()
	ghost_block.global_position = snap_to_grid(mouse_pos, ghost_block.size)

func snap_to_grid(pos:Vector2, block_size:Vector2) -> Vector2i:
	var snapped_pos = Vector2(
		floor(pos.x / GRID_SIZE),
		floor(pos.y / GRID_SIZE)
	)
	var snapped_global_position = snapped_pos * GRID_SIZE + Vector2(GRID_SIZE / 2, GRID_SIZE / 2)
	return snapped_global_position  # useful for tracking in a grid dictionary
