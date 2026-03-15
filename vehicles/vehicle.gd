class_name Vehicle
extends RigidBody2D

const TILE_SIZE := 16

@onready var tilemap : TileMapLayer = $TileMapLayer
@onready var collision_root : Node2D = $CollisionRoot
@onready var blocks_root : Node2D = $Blocks

# grid storage
var grid : Dictionary = {}      # Vector2i -> Block
var blocks : Array = []

# basic property
var total_mass := 0.0


# Block Management

func can_place_block(block_scene:PackedScene, cell:Vector2i) -> bool:
	var block = block_scene.instantiate()
	block.origin_cell = cell
	for c in block.get_occupied_cells():
		if grid.has(c):
			block.queue_free()
			return false
	block.queue_free()
	return true


func add_block(cell:Vector2i, block_scene):
	var block = block_scene.instantiate()
	block.initialize(self, cell)
	# check space
	for c in block.get_occupied_cells():
		if grid.has(c):
			return false
	# register cells
	for c in block.get_occupied_cells():
		grid[c] = block
	block.position = (cell * TILE_SIZE) + (block.size * TILE_SIZE) / 2
	blocks_root.add_child(block)
	create_collision(block)
	total_mass += block.mass
	mass = total_mass
	return true


func create_collision(block:Block):
	if block.collision != null:
		block.remove_child(block.collision)
		block.collision.position = block.position
		collision_root.add_child(block.collision)


func destroy_block(block:Block):
	for c in block.get_occupied_cells():
		grid.erase(c)
	block.collision.queue_free()
	block.queue_free()


# Physics Calculation

func calculate_center_of_mass() -> Vector2:
	if blocks.size() == 0:
		return Vector2.ZERO
	
	var weighted_sum := Vector2.ZERO
	var total_m := 0.0
	
	for block in blocks:
		var block_mass = block.mass
		# center position of the block
		var block_center = (block.origin_cell * TILE_SIZE) + (block.size * TILE_SIZE) / 2
		weighted_sum += block_center * block_mass
		total_m += block_mass
	
	return weighted_sum / total_m


# Convert screen/world position to vehicle grid cell
func screen_to_cell(screen_pos: Vector2) -> Vector2i:
	var world = get_viewport().get_camera_2d().unproject_position(screen_pos)
	var local = to_local(world)
	return Vector2i(
		floor(local.x / TILE_SIZE),
		floor(local.y / TILE_SIZE)
	)


# Convert cell → world position (for preview drawing)
func cell_to_world(cell: Vector2i) -> Vector2:
	var local = cell * TILE_SIZE
	return to_global(local)
