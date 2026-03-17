class_name Vehicle
extends RigidBody2D

const TILE_SIZE := Globals.TILE_SIZE

@onready var tilemap : TileMapLayer = $TileMapLayer
@onready var collision_root : Node2D = $CollisionRoot
@onready var blocks_root : Node2D = $Blocks

# grid storage
var grid : Dictionary = {}      # Vector2i -> Block
var blocks : Array = []

# basic property
var total_mass := 0.0
var com : Vector2


func _process(_delta):
	pass


func update_vehicle():
	com = calculate_center_of_mass()
	var mass_sum := 0
	for block in blocks:
		mass_sum += block.mass
	total_mass = mass_sum


# Block Management

func can_place_block(block:Block, cell:Vector2i) -> bool:
	block.origin_cell = cell
	for c in block.get_occupied_cells():
		if grid.has(c):
			block.queue_free()
			return false
	return true


func place_block(block_prototype:Block, cell:Vector2i, rotation_i:int):
	var block := block_prototype.duplicate() as Block
	block.update_transform(self, cell, rotation_i)
	# check space
	if not can_place_block(block, cell):
		block.queue_free()
		return false
	# register cells
	for c in block.get_occupied_cells():
		grid[c] = block
	
	blocks_root.add_child(block)
	blocks.append(block)
	create_collision(block)
	
	update_vehicle()
	
	return true


func create_collision(block:Block):
	if block.collision != null:
		block.remove_child(block.collision)
		block.collision.position = block.position
		collision_root.add_child(block.collision)


func destroy_block(block:Block):
	blocks.erase(block)
	for c in block.get_occupied_cells():
		grid.erase(c)
	block.collision.queue_free()
	block.queue_free()
	
	update_vehicle()


func get_block(cell:Vector2i):
	if grid.has(cell):
		return grid[cell]
	return null


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
		weighted_sum += Vector2(block_center) * block_mass
		total_m += block_mass
	
	return weighted_sum / total_m


# Convert screen/world position to vehicle grid cell
func world_to_cell(world_pos: Vector2) -> Vector2i:
	var local = to_local(world_pos)
	return Vector2i(
		floor(local.x / TILE_SIZE),
		floor(local.y / TILE_SIZE)
	)


# Convert cell → world position (for preview drawing)
func cell_to_world(cell: Vector2i) -> Vector2:
	var local = cell * TILE_SIZE
	return to_global(local)
