class_name Vehicle
extends RigidBody2D

const TILE_SIZE := Globals.TILE_SIZE

@onready var blocks_root : Node2D = $Blocks
# overlays
@onready var power_system := $PowerSystem

# grid storage
var grid : Dictionary = {}      # Vector2i -> Block
var blocks : Array[Block] = []

# basic property
var total_mass := 0.0
var total_engine_power: float = 0.0
var engines: Array[PowerPack] = []
var tracks: Array[Track] = []


func _process(_delta):
	pass


func update_vehicle():
	var mass_sum := 0
	for block in blocks:
		mass_sum += block.mass
	total_mass = mass_sum
	
	center_of_mass = calculate_center_of_mass()
	
	refresh_system_lists()


func get_drive_input() -> Dictionary:
	var v := 0.0
	if Input.is_action_pressed("FORWARD"):
		v += 1.0
	if Input.is_action_pressed("BACKWARD"):
		v -= 1.0
	
	var h := 0.0
	if Input.is_action_pressed("PIVOT_RIGHT"):
		h += 1.0
	if Input.is_action_pressed("PIVOT_LEFT"):
		h -= 1.0
	
	var input = {
		"move": clampf(v, -1.0, 1.0),
		"pivot": clamp(h, -1.0, 1.0)
		}
	
	return input


# Block Management

func can_place_block(block:Block, cell:Vector2i) -> bool:
	# 1. overlap check
	block.origin_cell = cell
	for c in block.get_occupied_cells():
		if grid.has(c):
			#block.queue_free()
			return false
	
	# 2. per-edge connectivity check
	var block_edges := block.get_transformed_edges()
	for edge_cell in block_edges.keys():
		var side_dict: Dictionary = block_edges[edge_cell]
		for side in side_dict.keys():
			var my_connectable: bool = side_dict[side]
			var neighbor_cell : Vector2i = edge_cell + Block.SIDE_DIRS[side]
			var neighbor := get_block(neighbor_cell)
			if neighbor == null:
				continue
			
			var opposite: int = Block.OPPOSITE_SIDE[side]
			var neighbor_connectable := neighbor.is_edge_connectable(neighbor_cell, opposite)
			
			if not my_connectable or not neighbor_connectable:
				return false
	
	return true


func place_block(block_scene:PackedScene, cell:Vector2i, rotation_i:int):
	var block := block_scene.instantiate() as Block
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
		block.collision.rotation = block.rotation
		add_child(block.collision)


func destroy_block(block:Block):
	blocks.erase(block)
	for c in block.get_occupied_cells():
		grid.erase(c)
	block.collision.queue_free()
	block.queue_free()
	
	update_vehicle()


func get_block(cell: Vector2i) -> Block:
	return grid.get(cell, null)


func refresh_system_lists() -> void:
	tracks.clear()
	engines.clear()
	
	total_engine_power = 0.0
	
	for block in blocks:
		if block is Track:
			tracks.append(block as Track)
		elif block is PowerPack:
			var engine := block as PowerPack
			engines.append(engine)
			total_engine_power += engine.power_output
	
	rebuild_tracks_connections()
	
	# systems update
	power_system.rebuild_drive_distribution()


# tracks
func rebuild_tracks_connections() -> void:
	var unvisited: Dictionary = {}
	for track in tracks:
		unvisited[track] = true
		track.update_local_neighbors()
	while not unvisited.is_empty():
		var start: Track = unvisited.keys()[0]
		var component := get_track_component(start)
		for track in component:
			track.connected_tracks = component.duplicate()
			unvisited.erase(track)


func get_track_component(start: Track) -> Array[Track]:
	var result: Array[Track] = []
	var visited: Dictionary = {}
	var queue: Array[Track] = [start]
	
	while not queue.is_empty():
		var current: Track = queue.pop_front()
		if visited.has(current):
			continue
		visited[current] = true
		result.append(current)
		if current.front_track != null and not visited.has(current.front_track):
			queue.append(current.front_track)
		if current.back_track != null and not visited.has(current.back_track):
			queue.append(current.back_track)
	return result


# Physics Calculation

func calculate_center_of_mass() -> Vector2:
	if blocks.size() == 0:
		return Vector2.ZERO
	
	var weighted_sum := Vector2.ZERO
	var total_m := 0.0
	
	for block in blocks:
		var block_mass = block.mass
		# center position of the block
		var block_COM = block.position
		weighted_sum += Vector2(block_COM) * block_mass
		total_m += block_mass
	
	return weighted_sum / total_m


# Convert world position to vehicle grid cell
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
