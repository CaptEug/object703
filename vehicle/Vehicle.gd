class_name Vehicle
extends RigidBody2D

signal vehicle_split(fragments: Array)

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
@export var owner_id: StringName = &"player"
var blueprint_blocks: Array = []
var blueprint_ghosts_root: Node2D
var total_mass := 0.0
var total_engine_power: float = 0.0
var engines: Array[PowerPack] = []
var tracks: Array[Track] = []
var control_blocks: Array[ControlBlock] = []
var active_control_block: ControlBlock


func _ready() -> void:
	add_to_group("vehicles")
	blueprint_ghosts_root = Node2D.new()
	blueprint_ghosts_root.name = "BlueprintGhosts"
	blueprint_ghosts_root.z_index = 20
	blueprint_ghosts_root.process_mode = Node.PROCESS_MODE_DISABLED
	blueprint_ghosts_root.visible = false
	add_child(blueprint_ghosts_root)


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
	mass = maxf(total_mass, 0.01)
	
	center_of_mass = calculate_center_of_mass()
	
	refresh_system_lists()
	refresh_blueprint_ghosts()


func get_drive_input() -> Dictionary:
	if not is_instance_valid(active_control_block):
		return {
			"move": 0.0,
			"pivot": 0.0,
		}
	return active_control_block.get_drive_command()


func has_aim_command() -> bool:
	return (
		is_instance_valid(active_control_block)
		and active_control_block.has_aim_command()
	)


func get_aim_target() -> Vector2:
	if not is_instance_valid(active_control_block):
		return global_position
	return active_control_block.get_aim_target()


func get_fire_command() -> bool:
	return (
		is_instance_valid(active_control_block)
		and active_control_block.get_fire_command()
	)


func set_active_control_block(control_block: ControlBlock) -> bool:
	if not is_instance_valid(control_block) or not control_blocks.has(control_block):
		return false
	active_control_block = control_block
	return true


# Block Management

func can_place_block(block:Block, cell:Vector2i) -> bool:
	# overlap check
	block.origin_cell = cell
	for c in block.get_occupied_cells():
		if grid.has(c):
			return false
	return true


func place_block(
	block_scene: PackedScene,
	cell: Vector2i,
	rotation_i: int,
	block_size: Vector2i = Vector2i.ZERO,
	merge_containers: bool = true
):
	var block := block_scene.instantiate() as Block
	if block == null:
		return false
	if block is ExpandableStorage:
		var container_size := (
			block.size
			if block_size == Vector2i.ZERO
			else block_size
		)
		if not (block as ExpandableStorage).configure_blueprint_size(
			container_size
		):
			block.free()
			return false
	elif block_size != Vector2i.ZERO and block_size != block.size:
		block.free()
		return false
	block.update_transform(self, cell, rotation_i)
	# check space
	if not can_place_block(block, cell):
		block.free()
		return false
	# register cells
	for c in block.get_occupied_cells():
		grid[c] = block
	
	blocks_root.add_child(block)
	blocks.append(block)
	create_collision(block)
	
	if merge_containers:
		merge_rectangular_containers()
	update_vehicle()
	reconcile_blueprint_with_blocks()
	
	return true


func create_collision(block: Block) -> void:
	if block.collision != null:
		var collision := block.collision
		var old_global := collision.global_transform
		
		block.remove_child(collision)
		add_child(collision)
		
		collision.global_transform = old_global


func merge_rectangular_containers() -> int:
	var unvisited := {}
	for block: Block in blocks:
		if block is ExpandableStorage:
			unvisited[block] = true

	var merged_count := 0
	while not unvisited.is_empty():
		var start := unvisited.keys()[0] as ExpandableStorage
		var component := _get_container_component(start, unvisited)
		if component.size() <= 1:
			continue
		var rectangle := _get_complete_container_rectangle(component)
		if rectangle.size == Vector2i.ZERO:
			continue
		if not start.can_merge_storage_members(component):
			continue
		_merge_container_component(component, rectangle)
		merged_count += 1
	return merged_count


func _get_container_component(
	start: ExpandableStorage,
	unvisited: Dictionary
) -> Array:
	var result: Array = []
	var queue: Array[ExpandableStorage] = [start]
	var merge_key := start.get_container_merge_key()
	var merge_rotation := start.rotation_index
	while not queue.is_empty():
		var current := queue.pop_front() as ExpandableStorage
		if not unvisited.has(current):
			continue
		unvisited.erase(current)
		result.append(current)
		for occupied_cell: Vector2i in current.get_occupied_cells():
			for direction: Vector2i in Block.SIDE_DIRS.values():
				var neighbor := get_block(occupied_cell + direction)
				if (
					neighbor is ExpandableStorage
					and neighbor != current
					and unvisited.has(neighbor)
					and (
						neighbor as ExpandableStorage
					).get_container_merge_key() == merge_key
					and (
						neighbor as ExpandableStorage
					).rotation_index == merge_rotation
				):
					queue.append(neighbor as ExpandableStorage)
	return result


func _get_complete_container_rectangle(component: Array) -> Rect2i:
	var occupied := {}
	var has_cell := false
	var min_cell := Vector2i.ZERO
	var max_cell := Vector2i.ZERO
	for value: Variant in component:
		var container := value as ExpandableStorage
		if container == null:
			continue
		for cell: Vector2i in container.get_occupied_cells():
			occupied[cell] = true
			if not has_cell:
				min_cell = cell
				max_cell = cell
				has_cell = true
			else:
				min_cell.x = mini(min_cell.x, cell.x)
				min_cell.y = mini(min_cell.y, cell.y)
				max_cell.x = maxi(max_cell.x, cell.x)
				max_cell.y = maxi(max_cell.y, cell.y)
	if not has_cell:
		return Rect2i()
	var rectangle_size := max_cell - min_cell + Vector2i.ONE
	if occupied.size() != rectangle_size.x * rectangle_size.y:
		return Rect2i()
	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			if not occupied.has(Vector2i(x, y)):
				return Rect2i()
	return Rect2i(min_cell, rectangle_size)


func _merge_container_component(
	component: Array,
	rectangle: Rect2i
) -> void:
	var leader := component[0] as ExpandableStorage
	for value: Variant in component:
		var candidate := value as ExpandableStorage
		if (
			candidate.origin_cell.y < leader.origin_cell.y
			or (
				candidate.origin_cell.y == leader.origin_cell.y
				and candidate.origin_cell.x < leader.origin_cell.x
			)
		):
			leader = candidate

	for value: Variant in component:
		var member := value as ExpandableStorage
		for occupied_cell: Vector2i in member.get_occupied_cells():
			grid.erase(occupied_cell)

	var merged_size := rectangle.size
	if leader.rotation_index % 2 != 0:
		merged_size = Vector2i(rectangle.size.y, rectangle.size.x)
	leader.merge_container_members(
		component,
		rectangle.position,
		merged_size,
		leader.rotation_index
	)

	for value: Variant in component:
		var member := value as ExpandableStorage
		if member == leader:
			continue
		blocks.erase(member)
		if member.collision != null:
			member.collision.queue_free()
		member.queue_free()

	for occupied_cell: Vector2i in leader.get_occupied_cells():
		grid[occupied_cell] = leader


func damage_block(cell: Vector2i, amount: int, type: String):
	var block := get_block(cell)
	if block == null:
		return false
	
	if amount <= 0.0:
		return false
	
	# apply damage
	block.damage(amount, type)


func destroy_block(block: Block) -> Array[Vehicle]:
	if block == null or not blocks.has(block):
		return []
	var preferred_control := active_control_block
	var original_com_global := to_global(center_of_mass)
	var original_linear_velocity := linear_velocity
	var original_angular_velocity := angular_velocity
	blocks.erase(block)
	for c in block.get_occupied_cells():
		grid.erase(c)
	if block.collision != null:
		block.collision.queue_free()
	block.queue_free()
	
	update_vehicle()
	var fragments := split_disconnected_components(
		preferred_control,
		original_com_global,
		original_linear_velocity,
		original_angular_velocity
	)
	if not fragments.is_empty():
		vehicle_split.emit(fragments)
	return fragments


func split_disconnected_components(
	preferred_control: ControlBlock = null,
	original_com_global: Vector2 = to_global(center_of_mass),
	original_linear_velocity: Vector2 = linear_velocity,
	original_angular_velocity: float = angular_velocity
) -> Array[Vehicle]:
	if block_components.size() <= 1:
		return []
	var components: Array = block_components.duplicate()
	var retained_component := _choose_retained_component(
		components,
		preferred_control
	)
	var parent := get_parent()
	if parent == null:
		return []

	var fragments: Array[Vehicle] = []
	for component_value: Variant in components:
		var component := component_value as Array
		if component == retained_component:
			continue
		var fragment := (
			load("res://vehicle/Vehicle.tscn").instantiate()
			as Vehicle
		)
		if fragment == null:
			continue
		fragment.owner_id = owner_id
		parent.add_child(fragment)
		fragment.global_transform = global_transform
		if _component_has_control(component):
			fragment.vehicle_name = "parts of %s" % vehicle_name
		else:
			fragment.vehicle_name = "debris of %s" % vehicle_name
		_move_component_to_vehicle(component, fragment)
		fragment.update_vehicle()
		fragment.replace_blueprint_from_blocks()
		fragment.angular_velocity = original_angular_velocity
		fragment.linear_velocity = _get_fragment_linear_velocity(
			fragment,
			original_com_global,
			original_linear_velocity,
			original_angular_velocity
		)
		fragment.sleeping = false
		fragments.append(fragment)

	update_vehicle()
	replace_blueprint_from_blocks()
	angular_velocity = original_angular_velocity
	linear_velocity = _get_fragment_linear_velocity(
		self,
		original_com_global,
		original_linear_velocity,
		original_angular_velocity
	)
	sleeping = false
	return fragments


func _choose_retained_component(
	components: Array,
	preferred_control: ControlBlock
) -> Array:
	if preferred_control != null:
		for component_value: Variant in components:
			var component := component_value as Array
			if component.has(preferred_control):
				return component

	for component_value: Variant in components:
		var component := component_value as Array
		if _component_has_control(component):
			return component

	var largest_component: Array = components[0]
	var largest_mass := _get_component_mass(largest_component)
	for component_value: Variant in components:
		var component := component_value as Array
		var component_mass := _get_component_mass(component)
		if component_mass > largest_mass:
			largest_component = component
			largest_mass = component_mass
	return largest_component


func _component_has_control(component: Array) -> bool:
	for block_value: Variant in component:
		if block_value is ControlBlock:
			return true
	return false


func _get_component_mass(component: Array) -> float:
	var component_mass := 0.0
	for block_value: Variant in component:
		var component_block := block_value as Block
		if component_block != null:
			component_mass += component_block.mass
	return component_mass


func _move_component_to_vehicle(
	component: Array,
	target_vehicle: Vehicle
) -> void:
	for block_value: Variant in component:
		var component_block := block_value as Block
		if component_block == null:
			continue
		blocks.erase(component_block)
		for occupied_cell: Vector2i in component_block.get_occupied_cells():
			grid.erase(occupied_cell)
			target_vehicle.grid[occupied_cell] = component_block
		component_block.reparent(target_vehicle.blocks_root, true)
		component_block.vehicle = target_vehicle
		target_vehicle.blocks.append(component_block)
		if component_block.collision != null:
			component_block.collision.reparent(target_vehicle, true)


func _get_fragment_linear_velocity(
	fragment: Vehicle,
	original_com_global: Vector2,
	original_linear_velocity: Vector2,
	original_angular_velocity: float
) -> Vector2:
	var fragment_com_global := fragment.to_global(fragment.center_of_mass)
	var radius := fragment_com_global - original_com_global
	var tangent := Vector2(-radius.y, radius.x) * original_angular_velocity
	return original_linear_velocity + tangent


func get_block(cell: Vector2i) -> Block:
	return grid.get(cell, null)


func refresh_system_lists() -> void:
	var previous_control := active_control_block
	tracks.clear()
	engines.clear()
	control_blocks.clear()
	
	total_engine_power = 0.0
	
	for block in blocks:
		if block is ControlBlock:
			control_blocks.append(block as ControlBlock)
		elif block is Track:
			tracks.append(block as Track)
		elif block is PowerPack:
			var engine := block as PowerPack
			engines.append(engine)
			total_engine_power += engine.max_power
	if is_instance_valid(previous_control) and control_blocks.has(previous_control):
		active_control_block = previous_control
	elif control_blocks.is_empty():
		active_control_block = null
	else:
		active_control_block = control_blocks[0]
	
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


func distance_to_world_point(world_point: Vector2) -> float:
	if blocks.is_empty():
		return global_position.distance_to(world_point)
	var nearest_distance := INF
	for block: Block in blocks:
		for cell: Vector2i in block.get_occupied_cells():
			var cell_center := (
				(Vector2(cell) + Vector2(0.5, 0.5)) * TILE_SIZE
			)
			nearest_distance = minf(
				nearest_distance,
				to_global(cell_center).distance_to(world_point)
			)
	return nearest_distance


# Blueprint

func set_blueprint_records(records: Array) -> void:
	blueprint_blocks = records.duplicate(true)
	blueprint_blocks.sort_custom(VehicleBlueprint._sort_block_records)
	refresh_blueprint_ghosts()


func ensure_blueprint_from_blocks() -> void:
	if blueprint_blocks.is_empty() and not blocks.is_empty():
		replace_blueprint_from_blocks()


func replace_blueprint_from_blocks() -> void:
	blueprint_blocks = VehicleBlueprint.capture_vehicle_blocks(self)
	refresh_blueprint_ghosts()


func reconcile_blueprint_with_blocks() -> void:
	blueprint_blocks = VehicleBlueprint.reconcile_records(
		blueprint_blocks,
		self
	)
	refresh_blueprint_ghosts()


func get_missing_blueprint_records() -> Array:
	var missing: Array = []
	for record: Array in blueprint_blocks:
		if VehicleBlueprint.get_matching_block(self, record) == null:
			missing.append(record.duplicate(true))
	return missing


func remove_blueprint_record_at_cell(cell: Vector2i) -> bool:
	for index in range(blueprint_blocks.size() - 1, -1, -1):
		if VehicleBlueprint.get_record_cells(blueprint_blocks[index]).has(cell):
			blueprint_blocks.remove_at(index)
			refresh_blueprint_ghosts()
			return true
	return false


func set_blueprint_ghosts_visible(visible: bool) -> void:
	if blueprint_ghosts_root == null:
		return
	blueprint_ghosts_root.visible = visible
	if visible:
		refresh_blueprint_ghosts()


func refresh_blueprint_ghosts() -> void:
	if blueprint_ghosts_root == null:
		return
	for child: Node in blueprint_ghosts_root.get_children():
		child.free()
	if not blueprint_ghosts_root.visible:
		return

	for record: Array in get_missing_blueprint_records():
		var scene := BlockDB.get_scene(int(record[0]))
		if scene == null:
			continue
		var ghost := scene.instantiate() as Block
		if ghost == null:
			continue
		var saved_size := VehicleBlueprint._get_record_size(record)
		if (
			saved_size != Vector2i.ZERO
			and ghost is ExpandableStorage
			and not (ghost as ExpandableStorage).configure_blueprint_size(
				saved_size
			)
		):
			ghost.free()
			continue
		ghost.process_mode = Node.PROCESS_MODE_DISABLED
		ghost.update_transform(
			self,
			Vector2i(int(record[1]), int(record[2])),
			int(record[3])
		)
		ghost.modulate = Color(1.0, 0.48, 0.08, 0.42)
		blueprint_ghosts_root.add_child(ghost)
		_disable_ghost_features(ghost)


func _disable_ghost_features(node: Node) -> void:
	if node is CollisionShape2D:
		(node as CollisionShape2D).disabled = true
	elif node is CollisionPolygon2D:
		(node as CollisionPolygon2D).disabled = true
	elif node is Area2D:
		(node as Area2D).monitoring = false
		(node as Area2D).monitorable = false
	for child: Node in node.get_children():
		_disable_ghost_features(child)
