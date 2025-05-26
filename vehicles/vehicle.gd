class_name Vehicle
extends Node2D

const GRID_SIZE:int = 16
var move_state:String
var total_power:float
var total_weight:int
var bluepirnt:Dictionary
var grid:= {}
var blocks:= []

# Called when the node enters the scene tree for the first time.
func _ready():
	for block in blocks:
		block.add_to_group("blocks")
	connect_blocks()
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	update_tracks_state(delta)
	pass

func connect_blocks():
	for block in get_tree().get_nodes_in_group('blocks'):
		var snapped_pos = snap_block_to_grid(block)
		grid[snapped_pos] = block
		connect_adjacent_blocks(snapped_pos, block)

func get_total_engine_power() -> float:
	var total_power := 0.0
	for engine in get_tree().get_nodes_in_group('engines'):
		if engine.is_inside_tree() and is_instance_valid(engine):
			total_power += engine.power
	return total_power



func update_tracks_state(delta):
	if Input.is_action_pressed("FORWARD"): 
		move_state = 'forward'
	elif Input.is_action_pressed("BACKWARD"):
		move_state = 'backward'
	else:
		move_state = 'idle'

func snap_block_to_grid(block:Block) -> Vector2i:
	var world_pos = block.global_position
	var snapped_pos = Vector2(
		floor(world_pos.x / GRID_SIZE),
		floor(world_pos.y / GRID_SIZE)
	)
	block.global_position = snapped_pos * GRID_SIZE + block.size/2 * GRID_SIZE
	return snapped_pos  # useful for tracking in a grid dictionary

func connect_adjacent_blocks(pos:Vector2i, block:Block):
	var directions = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for dir in directions:
		var neighbor_pos = pos + dir
		if grid.has(neighbor_pos):
			var neighbor = grid[neighbor_pos]
			connect_with_joint(block, neighbor, dir)

func connect_with_joint(a:Block, b:Block, dir):
	var joint = PinJoint2D.new()
	joint.node_a = a.get_path()
	joint.node_b = b.get_path()
	# Place joint in the middle of the two blocks
	if dir == Vector2i.LEFT:
		joint.position.x = - a.size.x * GRID_SIZE / 2.0
	if dir == Vector2i.RIGHT:
		joint.position.x = a.size.x * GRID_SIZE / 2.0
	if dir == Vector2i.UP:
		joint.position.y = - a.size.y * GRID_SIZE / 2.0
	if dir == Vector2i.DOWN:
		joint.position.y = a.size.y * GRID_SIZE / 2.0
	joint.disable_collision = false
	a.add_child(joint)
	
