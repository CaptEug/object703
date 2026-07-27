class_name Vehicle
extends RigidBody2D

const TILE_SIZE := Globals.TILE_SIZE

@onready var blocks_root : Node2D = $Blocks
@onready var power_system := $PowerSystem
@onready var fluid_system := $FluidSystem
@onready var supply_system := $SupplySystem

# grid storage
var grid : Dictionary = {}      # Vector2i -> Block
var blocks : Array[Block] = []
var block_components: Array[Array] = []
var block_component_map: Dictionary[Block, int] = {}

# basic property
@export var vehicle_name := "New Vehicle"
var total_mass := 0.0
var total_engine_power: float = 0.0
var engines: Array[PowerPack] = []
var tracks: Array[Track] = []


func _process(_delta):
	pass


func _input_event(viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not event is InputEventMouseButton:
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if _open_block_panel_at_mouse():
		viewport.set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if _open_block_panel_at_mouse():
		get_viewport().set_input_as_handled()


func _open_block_panel_at_mouse() -> bool:
	var block := get_block(world_to_cell(get_global_mouse_position()))
	if block == null:
		return false
	var panel := get_tree().get_first_node_in_group("block_information_panel")
	if panel != null and panel.has_method("open_for_block"):
		panel.open_for_block(block, get_viewport().get_mouse_position())
		return true
	return false


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
	# overlap check
	block.origin_cell = cell
	for c in block.get_occupied_cells():
		if grid.has(c):
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


func create_collision(block: Block) -> void:
	if block.collision != null:
		var collision := block.collision
		var old_global := collision.global_transform
		
		block.remove_child(collision)
		add_child(collision)
		
		collision.global_transform = old_global


func damage_block(cell: Vector2i, amount: int, type: String):
	var block := get_block(cell)
	if block == null:
		return false
	
	if amount <= 0.0:
		return false
	
	# apply damage
	block.damage(amount, type)


func destroy_block(block:Block):
	blocks.erase(block)
	for c in block.get_occupied_cells():
		grid.erase(c)
	if block.collision != null:
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
			total_engine_power += engine.max_power
	
	rebuild_block_connectivity()
	rebuild_tracks_connections()
	power_system.rebuild_drive_distribution()


func rebuild_block_connectivity() -> void:
	block_components.clear()
	block_component_map.clear()
	var unvisited := {}
	for block in blocks:
		unvisited[block] = true

	while not unvisited.is_empty():
		var start: Block = unvisited.keys()[0]
		var component: Array[Block] = []
		var queue: Array[Block] = [start]
		var component_index := block_components.size()

		while not queue.is_empty():
			var current: Block = queue.pop_front()
			if not unvisited.has(current):
				continue
			unvisited.erase(current)
			component.append(current)
			block_component_map[current] = component_index

			for neighbor in get_directly_connected_blocks(current):
				if unvisited.has(neighbor):
					queue.append(neighbor)

		block_components.append(component)

	for block in blocks:
		block.connected = get_connected_blocks(block, false).size() > 0
		block.connectivity_changed.emit()


func get_directly_connected_blocks(block: Block) -> Array[Block]:
	var result: Array[Block] = []
	for cell in block.get_occupied_cells():
		for side in Block.Side.values():
			var neighbor_cell: Vector2i = cell + Block.SIDE_DIRS[side]
			var neighbor := get_block(neighbor_cell)
			if neighbor == null or neighbor == block or result.has(neighbor):
				continue
			var opposite: int = Block.OPPOSITE_SIDE[side]
			if block.is_edge_connectable(cell, side) and neighbor.is_edge_connectable(neighbor_cell, opposite):
				result.append(neighbor)
	return result


func get_component_index(block: Block) -> int:
	return block_component_map.get(block, -1)


func are_blocks_connected(first: Block, second: Block) -> bool:
	var first_component := get_component_index(first)
	return first_component >= 0 and first_component == get_component_index(second)


func get_connected_blocks(block: Block, include_self: bool = true) -> Array[Block]:
	var component_index := get_component_index(block)
	if component_index < 0 or component_index >= block_components.size():
		return []
	var result: Array[Block] = []
	for connected_block in block_components[component_index]:
		if include_self or connected_block != block:
			result.append(connected_block)
	return result
	


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
