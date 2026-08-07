class_name Vehicle
extends RigidBody2D

signal vehicle_split(fragments: Array)

const TILE_SIZE := Globals.TILE_SIZE

@onready var blocks_root : Node2D = $Blocks
@onready var passive_visuals: TileMapLayer = $PassiveVisuals
@onready var power_system := $PowerSystem

# grid storage
var grid : Dictionary = {}      # Vector2i -> Block
var blocks : Array[Block] = []
var block_components: Array[Array] = []
var block_component_map: Dictionary[Block, int] = {}

# basic property
@export var vehicle_name := "New Vehicle"
var block_assembly: BlockAssembly
var _owner_id: StringName = &"player"
@export var owner_id: StringName:
	get:
		return block_assembly.owner_id if block_assembly != null else _owner_id
	set(value):
		_owner_id = value
		if block_assembly != null:
			block_assembly.owner_id = value
var blueprint_blocks: Array = []
var blueprint_ghosts_root: Node2D
var total_mass := 0.0
var tracks: Array[Track] = []
var control_blocks: Array[ControlBlock]:
	get:
		return (
			block_assembly.control_blocks
			if block_assembly != null
			else []
		)
var active_control_block: ControlBlock:
	get:
		return (
			block_assembly.active_control_block
			if block_assembly != null
			else null
		)


func _init() -> void:
	block_assembly = BlockAssembly.new(self)
	block_assembly.owner_id = _owner_id


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
	if (
		not event is InputEventMouseButton
		or not event.pressed
		or _panel_interaction_is_suppressed()
	):
		return
	var handled := false
	if event.button_index == MOUSE_BUTTON_LEFT:
		handled = open_panel()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		handled = _pin_hovered_block_panel()
	if handled:
		viewport.set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if (
		not event is InputEventMouseButton
		or not event.pressed
		or event.button_index != MOUSE_BUTTON_RIGHT
		or _panel_interaction_is_suppressed()
	):
		return
	if _pin_hovered_block_panel():
		get_viewport().set_input_as_handled()


func open_panel() -> bool:
	if _panel_interaction_is_suppressed():
		return false
	var panel := get_tree().get_first_node_in_group("vehicle_panel")
	if panel == null or not panel.has_method("open_for_vehicle"):
		return false
	var other_panel := get_tree().get_first_node_in_group("building_panel")
	if other_panel != null and other_panel.has_method("close_panel"):
		other_panel.close_panel()
	panel.open_for_vehicle(self)
	return true


func _pin_hovered_block_panel() -> bool:
	var panel := get_tree().get_first_node_in_group("block_information_panel")
	if panel != null and panel.has_method("pin_hovered_block"):
		return panel.pin_hovered_block(
			get_viewport().get_mouse_position()
		)
	return false


func _panel_interaction_is_suppressed() -> bool:
	var constructor := get_tree().get_first_node_in_group(
		"building_constructor"
	) as BuildingConstructor
	if constructor != null and constructor.is_active():
		return true
	var vehicle_editor := get_tree().get_first_node_in_group(
		"vehicle_editor"
	) as VehicleEditor
	return vehicle_editor != null and vehicle_editor.is_editing_vehicle()


func update_vehicle():
	var mass_sum := 0.0
	for block in blocks:
		mass_sum += block.mass
	total_mass = mass_sum
	mass = maxf(total_mass, 0.01)
	
	center_of_mass = calculate_center_of_mass()
	
	refresh_system_lists()
	refresh_blueprint_ghosts()


func get_drive_input() -> Dictionary:
	return block_assembly.get_drive_input()


func has_aim_command() -> bool:
	return block_assembly.has_aim_command()


func get_aim_target() -> Vector2:
	return (
		block_assembly.get_aim_target()
		if block_assembly.has_aim_command()
		else to_global(center_of_mass)
	)


func get_fire_command() -> bool:
	return block_assembly.get_fire_command()


func set_active_control_block(control_block: ControlBlock) -> bool:
	return block_assembly.set_active_control_block(control_block)


func has_control_block(control_block: ControlBlock) -> bool:
	return block_assembly.has_control_block(control_block)


func is_active_control_block(control_block: ControlBlock) -> bool:
	return block_assembly.is_active_control_block(control_block)


# Block Management

func can_place_block(block:Block, cell:Vector2i) -> bool:
	if (
		not BlockDB.has_block(block.block_id)
		or not BlockDB.can_place_on(
			block.block_id,
			BlockDB.HOST_VEHICLE
		)
	):
		return false
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
	merge_unions: bool = true,
	update_after_placement: bool = true
):
	var block := block_scene.instantiate() as Block
	if block == null:
		return false
	block.block_id = BlockDB.get_id_for_scene(block_scene.resource_path)
	if (
		block.block_id == BlockDB.INVALID_BLOCK_ID
		or not BlockDB.can_place_on(
			block.block_id,
			BlockDB.HOST_VEHICLE
		)
	):
		block.free()
		return false
	if block is ExpandableBlock:
		var union_size := (
			block.size
			if block_size == Vector2i.ZERO
			else block_size
		)
		if not (block as ExpandableBlock).configure_union_size(
			union_size
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
	refresh_block_visuals_around(block.get_occupied_cells())
	
	if merge_unions:
		merge_rectangular_unions()
	if update_after_placement:
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


func merge_rectangular_unions() -> int:
	var union_blocks: Array[ExpandableBlock] = []
	for block: Block in blocks:
		if block is ExpandableBlock:
			union_blocks.append(block as ExpandableBlock)
	var groups := ExpandableBlock.find_rectangular_groups(
		union_blocks,
		Callable(self, "get_block")
	)
	for group: Dictionary in groups:
		_merge_union_component(
			group["members"],
			group["rectangle"]
		)
	return groups.size()


func _merge_union_component(
	component: Array,
	rectangle: Rect2i
) -> void:
	var leader := component[0] as ExpandableBlock
	for value: Variant in component:
		var candidate := value as ExpandableBlock
		if (
			candidate.origin_cell.y < leader.origin_cell.y
			or (
				candidate.origin_cell.y == leader.origin_cell.y
				and candidate.origin_cell.x < leader.origin_cell.x
			)
		):
			leader = candidate

	for value: Variant in component:
		var member := value as ExpandableBlock
		for occupied_cell: Vector2i in member.get_occupied_cells():
			grid.erase(occupied_cell)

	var merged_size := rectangle.size
	if leader.rotation_index % 2 != 0:
		merged_size = Vector2i(rectangle.size.y, rectangle.size.x)
	leader.merge_union_members(
		component,
		rectangle.position,
		merged_size,
		leader.rotation_index
	)

	for value: Variant in component:
		var member := value as ExpandableBlock
		if member == leader:
			continue
		blocks.erase(member)
		if member.collision != null:
			member.collision.queue_free()
		member.queue_free()

	for occupied_cell: Vector2i in leader.get_occupied_cells():
		grid[occupied_cell] = leader


func destroy_block(block: Block) -> Array[Vehicle]:
	if block == null or not blocks.has(block):
		return []
	var preferred_control := active_control_block
	var original_com_global := to_global(center_of_mass)
	var original_linear_velocity := linear_velocity
	var original_angular_velocity := angular_velocity
	blocks.erase(block)
	var removed_cells := block.get_occupied_cells()
	for c in removed_cells:
		grid.erase(c)
	if block.collision != null:
		block.collision.queue_free()
	block.queue_free()
	refresh_block_visuals_around(removed_cells)
	
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


func get_block_damage_state(cell: Vector2i) -> Dictionary:
	var block := get_block(cell)
	if block == null:
		return {}
	return {
		"block": block,
		"block_id": block.block_id,
		"hp": block.hp,
	}


func commit_block_damage(
	state: Dictionary,
	result: Dictionary
) -> void:
	var block := state.get("block") as Block
	if not is_instance_valid(block) or not blocks.has(block):
		return
	block.apply_vehicle_damage_result(result)
	if result["destroyed"]:
		destroy_block(block)


func damage_block_at(
	cell: Vector2i,
	amount: float,
	damage_type: StringName
) -> Dictionary:
	return BlockDamage.apply_to_host(
		self,
		cell,
		amount,
		damage_type
	)


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
	var moved_cells: Array[Vector2i] = []
	for block_value: Variant in component:
		var component_block := block_value as Block
		if component_block == null:
			continue
		blocks.erase(component_block)
		for occupied_cell: Vector2i in component_block.get_occupied_cells():
			moved_cells.append(occupied_cell)
			grid.erase(occupied_cell)
			target_vehicle.grid[occupied_cell] = component_block
		component_block.reparent(target_vehicle.blocks_root, true)
		component_block.vehicle = target_vehicle
		component_block.block_host = target_vehicle
		component_block.assembly = target_vehicle.block_assembly
		target_vehicle.blocks.append(component_block)
		if component_block.collision != null:
			component_block.collision.reparent(target_vehicle, true)
	refresh_block_visuals_around(moved_cells)
	target_vehicle.refresh_block_visuals_around(moved_cells)


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


func get_block_id_at(cell: Vector2i) -> int:
	var block := get_block(cell)
	return (
		BlockDB.INVALID_BLOCK_ID
		if block == null
		else block.block_id
	)


func get_block_rotation_at(cell: Vector2i) -> int:
	var block := get_block(cell)
	return 0 if block == null else block.rotation_index


func get_visual_merge_data_at(cell: Vector2i) -> Dictionary:
	var block := get_block(cell)
	if block == null:
		return {}
	return {
		"group": BlockVisualSystem.get_block_merge_group(
			block.block_id
		),
		"rotation": block.rotation_index,
	}


func get_block_hp_at(cell: Vector2i) -> float:
	var block := get_block(cell)
	return 0.0 if block == null else block._local_hp


func get_assembly_at(_cell: Vector2i) -> BlockAssembly:
	return block_assembly


func refresh_block_visuals_around(cells: Array[Vector2i]) -> void:
	var affected_blocks := {}
	var affected_cells := {}
	for cell: Vector2i in cells:
		affected_cells[cell] = true
		var block := get_block(cell)
		if block != null:
			affected_blocks[block] = true
		for direction: Vector2i in (
			BlockVisualSystem.NEIGHBOR_DIRECTIONS
		):
			var neighbor_cell := cell + direction
			affected_cells[neighbor_cell] = true
			var neighbor := get_block(neighbor_cell)
			if neighbor != null:
				affected_blocks[neighbor] = true
	for block: Block in affected_blocks:
		var uses_tile_visual := (
			BlockVisualSystem.has_block_tile_visual(block.block_id)
		)
		_set_block_scene_sprite_visible(block, not uses_tile_visual)
		if not uses_tile_visual:
			block.refresh_shared_visual()
	for cell: Vector2i in affected_cells:
		_refresh_passive_visual_cell(cell)


func _refresh_passive_visual_cell(cell: Vector2i) -> void:
	var block := get_block(cell)
	if (
		block == null
		or not BlockVisualSystem.has_block_tile_visual(block.block_id)
	):
		passive_visuals.erase_cell(cell)
		return
	var variant := BlockVisualSystem.resolve_variant(
		self,
		cell,
		block.block_id,
		block.rotation_index
	)
	if variant.is_empty():
		passive_visuals.erase_cell(cell)
		return
	passive_visuals.set_cell(
		cell,
		int(variant["source_id"]),
		variant["atlas_coordinates"],
		int(variant.get("alternative", 0))
	)


func _set_block_scene_sprite_visible(
	block: Block,
	is_visible: bool
) -> void:
	var sprite := block.get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.visible = is_visible


func can_supply_item(
	requester: Block,
	item_name: String,
	amount: int
) -> bool:
	return block_assembly.can_supply_item(requester, item_name, amount)


func supply_item(
	requester: Block,
	item_name: String,
	amount: int
) -> bool:
	return block_assembly.supply_item(requester, item_name, amount)


func can_receive_item(
	requester: Block,
	item_name: String,
	amount: int = 1
) -> bool:
	return block_assembly.can_receive_item(requester, item_name, amount)


func receive_item(
	requester: Block,
	item_name: String,
	amount: int
) -> int:
	return block_assembly.receive_item(requester, item_name, amount)


func can_supply_liquids(
	requester: Block,
	liquid_requests: Dictionary
) -> bool:
	return block_assembly.can_supply_liquids(requester, liquid_requests)


func supply_liquids(
	requester: Block,
	liquid_requests: Dictionary
) -> bool:
	return block_assembly.supply_liquids(requester, liquid_requests)


func refresh_system_lists() -> void:
	var previous_control := active_control_block
	tracks.clear()
	
	for block in blocks:
		if block is Track:
			tracks.append(block as Track)
	block_assembly.rebuild(blocks, previous_control)
	
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


func get_layout_center_local() -> Vector2:
	var records := blueprint_blocks
	if records.is_empty():
		records = VehicleBlueprint.capture_vehicle_blocks(self)
	var bounds := VehicleBlueprint.get_records_bounds(records)
	if bounds.size == Vector2i.ZERO:
		return center_of_mass
	return (
		Vector2(bounds.position)
		+ Vector2(bounds.size) * 0.5
	) * TILE_SIZE


func normalize_layout_to_top_left() -> Vector2i:
	var records := blueprint_blocks.duplicate(true)
	records.append_array(VehicleBlueprint.capture_vehicle_blocks(self))
	var bounds := VehicleBlueprint.get_records_bounds(records)
	if bounds.size == Vector2i.ZERO:
		return Vector2i.ZERO
	rebase_grid_origin(bounds.position)
	return bounds.position


func rebase_grid_origin(cell_offset: Vector2i) -> void:
	if cell_offset == Vector2i.ZERO:
		return
	var local_offset := Vector2(cell_offset) * TILE_SIZE
	# Shift the origin while keeping every block at the same world position.
	global_position = global_transform * local_offset
	for record: Array in blueprint_blocks:
		record[1] = int(record[1]) - cell_offset.x
		record[2] = int(record[2]) - cell_offset.y

	grid.clear()
	var occupied_cells: Array[Vector2i] = []
	for block: Block in blocks:
		block.update_transform(
			self,
			block.origin_cell - cell_offset,
			block.rotation_index
		)
		if (
			is_instance_valid(block.collision)
			and block.collision.get_parent() == self
		):
			block.collision.position -= local_offset
		for cell: Vector2i in block.get_occupied_cells():
			grid[cell] = block
			occupied_cells.append(cell)

	passive_visuals.clear()
	update_vehicle()
	refresh_block_visuals_around(occupied_cells)


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
		ghost.block_id = int(record[0])
		var saved_size := VehicleBlueprint._get_record_size(record)
		if (
			saved_size != Vector2i.ZERO
			and ghost is ExpandableBlock
			and not (ghost as ExpandableBlock).configure_union_size(
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
