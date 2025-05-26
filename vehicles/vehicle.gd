class_name Vehicle
extends Node2D

var move_state:String
var total_power:float
var total_weight:int
var bluepirnt_grid:Dictionary

# Called when the node enters the scene tree for the first time.
func _ready():
	connect_blocks()
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	update_tracks_state(delta)
	pass

func connect_blocks():
	for block in get_tree().get_nodes_in_group('blocks'):
		var snapped_pos = snap_block_to_grid(block, 16, true)
		bluepirnt_grid[snapped_pos] = block
		connect_adjacent_blocks(snapped_pos, block)

func get_total_engine_power() -> float:
	var total_power := 0.0
	for engine in get_tree().get_nodes_in_group('engines'):
		if engine.is_inside_tree() and is_instance_valid(engine):
			total_power += engine.power
	return total_power

func set_total_track_liner_damp():
	for map in get_tree().get_nodes_in_group('maps'):
		print(map)
		if map.is_inside_tree() and is_instance_valid(map):
			var map_damp = map.stop_liner_damp_()
			for track in get_tree().get_nodes_in_group("tracks"):
				if track.is_inside_tree() and is_instance_valid(track):
					track.stopped_damp = map_damp
					track.set_liner_damp()
			break



func update_tracks_state(delta):
	if Input.is_action_pressed("FORWARD"): 
		move_state = 'forward'
	elif Input.is_action_pressed("BACKWARD"):
		move_state = 'backward'
	else:
		move_state = 'idle'

func snap_block_to_grid(block: Block, grid_size: int = 16, align_to_center: bool = true) -> Vector2i:
	var world_pos = block.global_position
	var snapped_pos = Vector2(
		floor(world_pos.x / grid_size),
		floor(world_pos.y / grid_size)
	)
	if align_to_center:
		block.global_position = snapped_pos * grid_size + Vector2(grid_size / 2, grid_size / 2)
	else:
		block.global_position = snapped_pos * grid_size
	return snapped_pos  # useful for tracking in a grid dictionary

func connect_adjacent_blocks(pos: Vector2i, block: Block):
	var directions = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for dir in directions:
		var neighbor_pos = pos + dir
		if bluepirnt_grid.has(neighbor_pos):
			var neighbor = bluepirnt_grid[neighbor_pos]
			connect_with_joint(block, neighbor)
			
func connect_with_joint(a: Block, b: Block):
	var joint = PinJoint2D.new()
	joint.node_a = a.get_path()
	joint.node_b = b.get_path()
	# Place joint in the middle of the two blocks
	joint.position = (a.global_position + b.global_position) / 2.0
	joint.disable_collision = false
	add_child(joint)
