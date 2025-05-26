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
	if ghost_block:
		update_ghost_position()
	pass

func update_ghost_position():
	var mouse_pos = get_global_mouse_position()
	var grid_pos = snap_to_grid(mouse_pos)
	ghost_block.global_position = grid_pos * GRID_SIZE + ghost_block.size/2 * GRID_SIZE

func place_block():
	var grid_pos = snap_to_grid(ghost_block.global_position)
	var size = ghost_block.size
	for x in size.x:
		for y in size.y:
			var cell = grid_pos + Vector2i(x, y)
			if placed_blocks.has(cell):
				return  # can't place here
	var block = block_scenes[current_block_type].instantiate()
	block.global_position = ghost_block.global_position
	add_child(block)
	# Mark all occupied cells
	for x in size.x:
		for y in size.y:
			var cell = grid_pos + Vector2i(x, y)
			placed_blocks[cell] = block

func snap_to_grid(pos:Vector2) -> Vector2i:
	var snapped_pos = Vector2(
		floor(pos.x / GRID_SIZE),
		floor(pos.y / GRID_SIZE)
	)
	return snapped_pos  # useful for tracking in a grid dictionary

func create_vehicle_from_grid():
	var vehicle = preload("res://vehicles/vehicle.tscn").instantiate()
	get_tree().get_root().add_child(vehicle)  # Or add to your scene
	var added = []
	for grid_pos in placed_blocks:
		var block = placed_blocks[grid_pos]
		if block in added:
			continue
		# Move block under vehicle
		block.get_parent().remove_child(block)
		vehicle.blocks.append(block)
		added.append(block)
		# Keep a grid index → block map
		vehicle.blueprint[grid_pos] = block
