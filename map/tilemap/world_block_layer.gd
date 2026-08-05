class_name WorldBlockLayer
extends TileMapLayer

signal block_placed(anchor: Vector2i, block_id: int)
signal block_damaged(anchor: Vector2i, result: Dictionary)
signal block_destroyed(anchor: Vector2i, block_id: int)
signal buildings_rebuilt(buildings: Array[Building])

const INVALID_CELL := Vector2i(-2147483648, -2147483648)

# One record per placed block, keyed by its anchor. Every occupied grid cell
# maps back to that anchor, allowing multi-cell blocks to share one HP value.
var block_records: Dictionary[Vector2i, Dictionary] = {}
var cell_occupancy: Dictionary[Vector2i, Vector2i] = {}
var functional_nodes: Dictionary[Vector2i, Block] = {}
var buildings: Array[Building]:
	get:
		return (
			building_system.buildings
			if building_system != null
			else []
		)

var _bulk_edit_depth := 0
var _pending_visual_cells: Dictionary = {}

@onready var gamemap: GameMap = get_parent()
@onready var functional_root: Node2D = get_node_or_null(
	"FunctionalBlocks"
) as Node2D
@onready var building_system: BuildingSystem = get_node_or_null(
	"BuildingSystem"
) as BuildingSystem


func _ready() -> void:
	add_to_group("world_block_layers")
	if functional_root == null:
		functional_root = Node2D.new()
		functional_root.name = "FunctionalBlocks"
		add_child(functional_root)
	if building_system == null:
		building_system = BuildingSystem.new()
		building_system.name = "BuildingSystem"
		add_child(building_system)
	building_system.setup(self)
	if not building_system.buildings_rebuilt.is_connected(
		_on_buildings_rebuilt
	):
		building_system.buildings_rebuilt.connect(
			_on_buildings_rebuilt
		)


func _on_buildings_rebuilt(rebuilt: Array[Building]) -> void:
	buildings_rebuilt.emit(rebuilt)


func _unhandled_input(event: InputEvent) -> void:
	if (
		not event is InputEventMouseButton
		or not event.pressed
		or _block_interaction_is_suppressed()
	):
		return
	var cell := local_to_map(to_local(get_global_mouse_position()))
	var handled := false
	if event.button_index == MOUSE_BUTTON_RIGHT:
		handled = open_information_panel_at(
			cell,
			get_viewport().get_mouse_position()
		)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		handled = open_building_panel_at(cell)
	if handled:
		get_viewport().set_input_as_handled()


func begin_bulk_edit() -> void:
	_bulk_edit_depth += 1
	building_system.begin_bulk_edit()


func end_bulk_edit() -> void:
	_bulk_edit_depth = maxi(_bulk_edit_depth - 1, 0)
	building_system.end_bulk_edit()
	if _bulk_edit_depth > 0:
		return
	_flush_visual_updates()


func initialize_from_tilemap() -> void:
	building_system.clear()
	block_records.clear()
	cell_occupancy.clear()
	for child: Node in functional_root.get_children():
		child.queue_free()
	functional_nodes.clear()

	for cell: Vector2i in get_used_cells():
		var tile_data := get_cell_tile_data(cell)
		if tile_data == null:
			continue
		var stored_id := int(tile_data.get_custom_data("block_id"))
		var block_id := (
			stored_id
			if BlockDB.has_block(stored_id)
			else BlockDB.INVALID_BLOCK_ID
		)
		if block_id == BlockDB.INVALID_BLOCK_ID:
			continue
		_register_block_state(
			cell,
			block_id,
			0,
			BlockDB.get_max_hp(block_id)
		)
	building_system.rebuild_all()


func get_block_anchor(cell: Vector2i) -> Vector2i:
	return cell_occupancy.get(cell, INVALID_CELL)


func get_block_state(cell: Vector2i) -> Dictionary:
	var anchor := get_block_anchor(cell)
	if anchor == INVALID_CELL:
		return {}
	return block_records.get(anchor, {})


func get_celldata(cell: Vector2i) -> Dictionary:
	return get_block_state(cell)


func get_block_id_at(cell: Vector2i) -> int:
	return int(
		get_block_state(cell).get(
			"block_id",
			BlockDB.INVALID_BLOCK_ID
		)
	)


func get_block_rotation_at(cell: Vector2i) -> int:
	return int(get_block_state(cell).get("rotation", 0))


func get_visual_merge_data_at(cell: Vector2i) -> Dictionary:
	var state := get_block_state(cell)
	if state.is_empty():
		return {}
	var block_id := int(state["block_id"])
	return {
		"group": BlockVisualSystem.get_block_merge_group(block_id),
		"rotation": int(state.get("rotation", 0)),
	}


func get_block_hp_at(cell: Vector2i) -> float:
	return float(get_block_state(cell).get("hp", 0.0))


func get_functional_block_at(cell: Vector2i) -> Block:
	var anchor := get_block_anchor(cell)
	return functional_nodes.get(anchor, null)


func open_information_panel_at(
	cell: Vector2i,
	screen_position: Vector2 = Vector2.ZERO
) -> bool:
	if _block_interaction_is_suppressed():
		return false
	var block := get_functional_block_at(cell)
	if block == null or not block.has_information_panel():
		return false
	var panel := get_tree().get_first_node_in_group(
		"block_information_panel"
	)
	if panel == null or not panel.has_method("open_for_block"):
		return false
	return panel.open_for_block(block, screen_position)


func open_building_panel_at(cell: Vector2i) -> bool:
	if _block_interaction_is_suppressed():
		return false
	return building_system.open_panel_at(cell)


func _block_interaction_is_suppressed() -> bool:
	var constructor := get_tree().get_first_node_in_group(
		"building_constructor"
	)
	if constructor != null and constructor.is_active():
		return true
	var vehicle_editor := get_tree().get_first_node_in_group(
		"vehicle_editor"
	)
	return (
		vehicle_editor != null
		and vehicle_editor.has_method("is_editing_vehicle")
		and vehicle_editor.is_editing_vehicle()
	)


func get_building_at(cell: Vector2i) -> Building:
	return (
		building_system.get_building_at(cell)
		if building_system != null
		else null
	)


func get_assembly_at(cell: Vector2i) -> BlockAssembly:
	var building := get_building_at(cell)
	return building.block_assembly if building != null else null


func get_solid_cell_at_world_position(
	world_position: Vector2,
	travel_direction: Vector2 = Vector2.ZERO
) -> Vector2i:
	var sample_position := world_position
	if not travel_direction.is_zero_approx():
		sample_position += travel_direction.normalized()
	var cell := local_to_map(to_local(sample_position))
	return cell if cell_occupancy.has(cell) else INVALID_CELL


func can_place_block(
	block_id: int,
	anchor: Vector2i,
	rotation_index: int = 0,
	owner_id: StringName = &"player"
) -> bool:
	if (
		not BlockDB.has_block(block_id)
		or BlockDB.is_liquid(block_id)
		or not BlockDB.can_place_on(block_id, BlockDB.HOST_WORLD)
	):
		return false
	var normalized_rotation := BlockDB.normalize_rotation(
		block_id,
		rotation_index
	)
	var occupied_cells := _get_occupied_cells(
		block_id,
		anchor,
		normalized_rotation
	)
	for cell: Vector2i in occupied_cells:
		if (
			gamemap != null
			and not gamemap.is_cell_in_world(cell)
		):
			return false
		if cell_occupancy.has(cell):
			return false
		if (
			gamemap != null
			and is_instance_valid(gamemap.liquid)
			and gamemap.liquid.get_block_id_at(cell)
			!= BlockDB.INVALID_BLOCK_ID
		):
			return false

	if not BlockDB.is_constructed(block_id):
		return true
	return building_system.can_place_for_owner(
		occupied_cells,
		owner_id
	)


func place_block(
	block_id: int,
	anchor: Vector2i,
	rotation_index: int = 0,
	hp: float = -1.0,
	owner_id: StringName = &"player"
) -> bool:
	if not can_place_block(
		block_id,
		anchor,
		rotation_index,
		owner_id
	):
		return false
	var normalized_rotation := BlockDB.normalize_rotation(
		block_id,
		rotation_index
	)
	var initial_hp := (
		BlockDB.get_max_hp(block_id)
		if hp < 0.0
		else clampf(hp, 0.0, BlockDB.get_max_hp(block_id))
	)
	var changed_cells := _get_occupied_cells(
		block_id,
		anchor,
		normalized_rotation
	)
	_register_block_state(
		anchor,
		block_id,
		normalized_rotation,
		initial_hp
	)
	if BlockDB.is_world_functional(block_id):
		_spawn_functional_node(anchor)
	else:
		_render_passive_block(anchor)

	var expandable := functional_nodes.get(
		anchor,
		null
	) as ExpandableBlock
	if expandable != null:
		merge_rectangular_union_from(expandable)
	if BlockDB.is_constructed(block_id):
		building_system.notify_constructed_changed(
			changed_cells,
			owner_id
		)
	var placed_anchor := get_block_anchor(anchor)
	if placed_anchor != INVALID_CELL:
		_queue_visual_refresh(
			_get_record_occupied_cells(placed_anchor)
		)
	block_placed.emit(anchor, block_id)
	return true


func get_block_damage_state(cell: Vector2i) -> Dictionary:
	var anchor := get_block_anchor(cell)
	if anchor == INVALID_CELL:
		return {}
	var state: Dictionary = block_records[anchor]
	return {
		"anchor": anchor,
		"block_id": int(state["block_id"]),
		"hp": float(state["hp"]),
	}


func commit_block_damage(
	damage_state: Dictionary,
	result: Dictionary
) -> void:
	var anchor: Vector2i = damage_state.get("anchor", INVALID_CELL)
	if anchor == INVALID_CELL or not block_records.has(anchor):
		return
	var state: Dictionary = block_records[anchor]
	var block_id := int(state["block_id"])
	if block_id != int(damage_state.get("block_id", -1)):
		return
	state["hp"] = result["hp_after"]
	var functional_block: Block = functional_nodes.get(anchor, null)
	if functional_block != null:
		functional_block.notify_world_health_changed(
			bool(result["destroyed"])
		)
	block_damaged.emit(anchor, result)
	if result["destroyed"]:
		destroy_block_at(anchor)
	elif randf() < 0.1:
		_spawn_block_shards(anchor, block_id)


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


func apply_radial_damage(
	world_position: Vector2,
	radius_tiles: int,
	max_damage: float
) -> int:
	if max_damage <= 0.0:
		return 0
	var center_cell := local_to_map(to_local(world_position))
	var damage_by_anchor: Dictionary = {}
	var scan_radius := maxi(radius_tiles, 0)
	for y in range(-scan_radius, scan_radius + 1):
		for x in range(-scan_radius, scan_radius + 1):
			var cell := center_cell + Vector2i(x, y)
			var anchor := get_block_anchor(cell)
			if anchor == INVALID_CELL:
				continue
			var cell_world := to_global(map_to_local(cell))
			var distance_tiles := (
				world_position.distance_to(cell_world)
				/ float(Globals.TILE_SIZE)
			)
			if radius_tiles > 0 and distance_tiles > float(radius_tiles):
				continue
			var factor := (
				1.0
				if radius_tiles <= 0
				else 1.0 - distance_tiles / float(radius_tiles)
			)
			var damage := max_damage * factor
			damage_by_anchor[anchor] = maxf(
				float(damage_by_anchor.get(anchor, 0.0)),
				damage
			)

	var damaged_blocks := 0
	for anchor: Vector2i in damage_by_anchor:
		var result := damage_block_at(
			anchor,
			float(damage_by_anchor[anchor]),
			&"EXPLOSIVE"
		)
		if result["hit"]:
			damaged_blocks += 1
	return damaged_blocks


func destroy_block_at(
	cell: Vector2i,
	spawn_shards: bool = true
) -> bool:
	var anchor := get_block_anchor(cell)
	if anchor == INVALID_CELL:
		return false
	var state: Dictionary = block_records.get(anchor, {})
	if state.is_empty():
		return false
	var block_id := int(state["block_id"])
	var occupied_cells := _get_record_occupied_cells(anchor)
	if spawn_shards:
		_spawn_block_shards(anchor, block_id)

	var functional_block: Block = functional_nodes.get(anchor, null)
	if functional_block != null:
		functional_nodes.erase(anchor)
		functional_block.queue_free()
	for occupied_cell: Vector2i in occupied_cells:
		cell_occupancy.erase(occupied_cell)
		erase_cell(occupied_cell)
	block_records.erase(anchor)

	_queue_visual_refresh(occupied_cells)
	if BlockDB.is_constructed(block_id):
		building_system.notify_constructed_changed(
			occupied_cells
		)
	_update_minimap(occupied_cells)
	block_destroyed.emit(anchor, block_id)
	return true


func destroy_tile(cell: Vector2i) -> bool:
	return destroy_block_at(cell)


func rebuild_buildings() -> void:
	building_system.rebuild_all()


func get_constructed_save_data() -> Array:
	return building_system.get_constructed_save_data()


func restore_constructed_save_data(records: Array) -> void:
	building_system.restore_constructed_save_data(records)


func save_chunk(
	chunk_x: int,
	chunk_y: int,
	world_origin: Vector2i = Vector2i.ZERO
) -> PackedByteArray:
	const CHUNK_SIZE := 32
	var bytes := PackedByteArray()
	for ly in range(CHUNK_SIZE):
		for lx in range(CHUNK_SIZE):
			var cell := Vector2i(
				world_origin.x + chunk_x * CHUNK_SIZE + lx,
				world_origin.y + chunk_y * CHUNK_SIZE + ly
			)
			var anchor := get_block_anchor(cell)
			var state: Dictionary = block_records.get(anchor, {})
			if (
				anchor != cell
				or (
					not state.is_empty()
					and not BlockDB.is_natural(int(state["block_id"]))
				)
			):
				state = {}
			var offset := bytes.size()
			bytes.resize(offset + 4)
			if state.is_empty():
				bytes.encode_u16(offset, 0)
				bytes.encode_u16(offset + 2, 0)
				continue
			var block_id := int(state["block_id"])
			bytes.encode_u16(offset, block_id)
			var max_hp := get_state_max_hp(
				block_id,
				state.get("size", BlockDB.get_size(block_id))
			)
			var health := clampi(
				roundi(float(state["hp"]) / maxf(max_hp, 0.001) * 65535.0),
				0,
				65535
			)
			bytes.encode_u16(offset + 2, health)
	return bytes


func load_chunk(
	chunk_x: int,
	chunk_y: int,
	bytes: PackedByteArray,
	chunk_size: int,
	world_origin: Vector2i = Vector2i.ZERO
) -> void:
	var expected_size := chunk_size * chunk_size * 4
	if bytes.size() < expected_size:
		push_error("Natural block chunk is truncated.")
		return
	var index := 0
	for ly in range(chunk_size):
		for lx in range(chunk_size):
			var block_id := bytes.decode_u16(index)
			var health := bytes.decode_u16(index + 2)
			index += 4
			if block_id == 0:
				continue
			if (
				not BlockDB.has_block(block_id)
				or not BlockDB.is_natural(block_id)
			):
				push_error(
					"Invalid natural block ID %d in chunk."
					% block_id
				)
				continue
			var cell := Vector2i(
				world_origin.x + chunk_x * chunk_size + lx,
				world_origin.y + chunk_y * chunk_size + ly
			)
			var hp := (
				BlockDB.get_max_hp(block_id)
				* float(health)
				/ 65535.0
			)
			place_block(block_id, cell, 0, hp)
func restore_constructed_block(
	block_id: int,
	anchor: Vector2i,
	rotation_index: int,
	hp: float,
	block_size: Vector2i,
	functional_state: Dictionary,
	owner_id: StringName
) -> bool:
	if (
		not BlockDB.has_block(block_id)
		or not BlockDB.is_constructed(block_id)
		or not BlockDB.can_place_on(block_id, BlockDB.HOST_WORLD)
		or block_size.x <= 0
		or block_size.y <= 0
	):
		return false
	var normalized_rotation := BlockDB.normalize_rotation(
		block_id,
		rotation_index
	)
	var occupied_cells := _get_occupied_cells(
		block_id,
		anchor,
		normalized_rotation,
		block_size
	)
	for cell: Vector2i in occupied_cells:
		if cell_occupancy.has(cell):
			return false
		if (
			gamemap != null
			and not gamemap.is_cell_in_world(cell)
		):
			return false
	_register_block_state(
		anchor,
		block_id,
		normalized_rotation,
		clampf(hp, 0.0, get_state_max_hp(block_id, block_size)),
		block_size
	)
	if BlockDB.is_world_functional(block_id):
		_spawn_functional_node(anchor)
		var functional := functional_nodes.get(anchor, null) as Block
		if functional != null:
			functional.apply_save_state(functional_state)
	else:
		_render_passive_block(anchor)
	building_system.notify_constructed_changed(
		occupied_cells,
		owner_id
	)
	_queue_visual_refresh(occupied_cells)
	block_placed.emit(anchor, block_id)
	return true


func _register_block_state(
	anchor: Vector2i,
	block_id: int,
	rotation_index: int,
	hp: float,
	block_size: Vector2i = Vector2i.ZERO
) -> void:
	if block_size == Vector2i.ZERO:
		block_size = BlockDB.get_size(block_id)
	block_records[anchor] = {
		"block_id": block_id,
		"hp": hp,
		"rotation": rotation_index,
		"size": block_size,
	}
	for cell: Vector2i in _get_occupied_cells(
		block_id,
		anchor,
		rotation_index,
		block_size
	):
		cell_occupancy[cell] = anchor


func get_state_max_hp(
	block_id: int,
	block_size: Vector2i = Vector2i.ZERO
) -> float:
	var base_size := BlockDB.get_size(block_id)
	if block_size == Vector2i.ZERO:
		block_size = base_size
	var base_units := maxi(base_size.x * base_size.y, 1)
	var stored_units := maxi(block_size.x * block_size.y, 1)
	return (
		BlockDB.get_max_hp(block_id)
		* float(stored_units)
		/ float(base_units)
	)


func _get_occupied_cells(
	block_id: int,
	anchor: Vector2i,
	rotation_index: int,
	block_size: Vector2i = Vector2i.ZERO
) -> Array[Vector2i]:
	if block_size == Vector2i.ZERO:
		block_size = BlockDB.get_size(block_id)
	if rotation_index % 2 != 0:
		block_size = Vector2i(block_size.y, block_size.x)
	var cells: Array[Vector2i] = []
	for y in range(block_size.y):
		for x in range(block_size.x):
			cells.append(anchor + Vector2i(x, y))
	return cells


func _get_record_occupied_cells(anchor: Vector2i) -> Array[Vector2i]:
	var state: Dictionary = block_records.get(anchor, {})
	if state.is_empty():
		return []
	return _get_occupied_cells(
		int(state["block_id"]),
		anchor,
		int(state.get("rotation", 0)),
		state.get("size", Vector2i.ZERO)
	)


func get_record_occupied_cells(anchor: Vector2i) -> Array[Vector2i]:
	return _get_record_occupied_cells(anchor)


func merge_rectangular_union_from(start: ExpandableBlock) -> bool:
	var group := ExpandableBlock.find_rectangular_group_from(
		start,
		Callable(self, "get_functional_block_at")
	)
	if group.is_empty():
		return false
	_merge_union_component(group["members"], group["rectangle"])
	return true


func _merge_union_component(
	component: Array,
	rectangle: Rect2i
) -> void:
	var leader := component[0] as ExpandableBlock
	var combined_hp := 0.0
	var old_cells: Array[Vector2i] = []
	for value: Variant in component:
		var member := value as ExpandableBlock
		if member == null:
			continue
		if (
			member.origin_cell.y < leader.origin_cell.y
			or (
				member.origin_cell.y == leader.origin_cell.y
				and member.origin_cell.x < leader.origin_cell.x
			)
		):
			leader = member
		var member_state: Dictionary = block_records.get(
			member.origin_cell,
			{}
		)
		combined_hp += float(member_state.get("hp", member.hp))
		for cell: Vector2i in member.get_occupied_cells():
			if not old_cells.has(cell):
				old_cells.append(cell)

	var block_id := leader.block_id
	var rotation_index := leader.rotation_index
	var merged_size := rectangle.size
	if rotation_index % 2 != 0:
		merged_size = Vector2i(rectangle.size.y, rectangle.size.x)

	leader.merge_union_members(
		component,
		rectangle.position,
		merged_size,
		rotation_index
	)
	for value: Variant in component:
		var member := value as ExpandableBlock
		if member == null:
			continue
		functional_nodes.erase(member.origin_cell)
		block_records.erase(member.origin_cell)
	for cell: Vector2i in old_cells:
		cell_occupancy.erase(cell)

	_register_block_state(
		rectangle.position,
		block_id,
		rotation_index,
		combined_hp,
		merged_size
	)
	functional_nodes[rectangle.position] = leader
	var collision_body := leader.get_node_or_null(
		"WorldCollision"
	) as WorldBlockBody
	if collision_body != null:
		collision_body.configure(self, rectangle.position)

	for value: Variant in component:
		var member := value as ExpandableBlock
		if member != null and member != leader:
			member.queue_free()
	_queue_visual_refresh(old_cells)


func _render_passive_block(anchor: Vector2i) -> void:
	var state: Dictionary = block_records[anchor]
	var block_id := int(state["block_id"])
	var variant := BlockVisualSystem.resolve_variant(
		self,
		anchor,
		block_id,
		int(state.get("rotation", 0))
	)
	if variant.is_empty():
		return
	set_cell(
		anchor,
		int(variant["source_id"]),
		variant["atlas_coordinates"],
		int(variant.get("alternative", 0))
	)


func _spawn_functional_node(anchor: Vector2i) -> void:
	var state: Dictionary = block_records[anchor]
	var block_id := int(state["block_id"])
	var scene := BlockDB.get_scene(block_id)
	if scene == null:
		push_error(
			"Functional world block %s has no scene."
			% BlockDB.get_block_name(block_id)
		)
		return
	var block := scene.instantiate() as Block
	if block == null:
		push_error("Functional scene is not a Block: %s." % scene.resource_path)
		return
	block.block_id = block_id
	if block is ExpandableBlock:
		var stored_size: Vector2i = state.get(
			"size",
			BlockDB.get_size(block_id)
		)
		if stored_size != block.size:
			(block as ExpandableBlock).configure_union_size(
				stored_size
			)
	block.update_world_transform(
		self,
		anchor,
		int(state.get("rotation", 0))
	)
	functional_root.add_child(block)
	functional_nodes[anchor] = block
	_attach_world_collision(block, anchor)


func _attach_world_collision(
	block: Block,
	anchor: Vector2i
) -> void:
	if block.collision == null:
		return
	var collision := block.collision
	var previous_transform := collision.transform
	block.remove_child(collision)
	var body := WorldBlockBody.new()
	body.name = "WorldCollision"
	body.configure(self, anchor)
	block.add_child(body)
	body.add_child(collision)
	collision.transform = previous_transform


func _queue_visual_refresh(cells: Array[Vector2i]) -> void:
	for cell: Vector2i in cells:
		_pending_visual_cells[cell] = true
		for direction: Vector2i in BlockVisualSystem.NEIGHBOR_DIRECTIONS:
			_pending_visual_cells[cell + direction] = true
	if _bulk_edit_depth == 0:
		_flush_visual_updates()


func _flush_visual_updates() -> void:
	if _pending_visual_cells.is_empty():
		return
	for cell: Vector2i in _pending_visual_cells:
		var block_id := get_block_id_at(cell)
		if block_id == BlockDB.INVALID_BLOCK_ID:
			continue
		if BlockVisualSystem.block_uses_merge_mask(block_id):
			var anchor := get_block_anchor(cell)
			var state: Dictionary = block_records[anchor]
			var variant: Dictionary = BlockVisualSystem.resolve_variant(
				self,
				cell,
				block_id,
				int(state.get("rotation", 0))
			)
			var functional_block: Block = functional_nodes.get(
				anchor,
				null
			)
			if functional_block != null:
				var sprite := functional_block.get_node_or_null(
					"Sprite2D"
				) as Sprite2D
				BlockVisualSystem.apply_variant_to_sprite(
					sprite,
					variant
				)
			elif not variant.is_empty():
				set_cell(
					cell,
					int(variant["source_id"]),
					variant["atlas_coordinates"],
					int(variant.get("alternative", 0))
				)
	_pending_visual_cells.clear()


func _spawn_block_shards(
	anchor: Vector2i,
	block_id: int
) -> void:
	var particle_path := str(
		BlockDB.get_block(block_id).get("particle_path", "")
	)
	if particle_path.is_empty():
		return
	var particle_scene := load(particle_path) as PackedScene
	if particle_scene == null:
		return
	var shard := particle_scene.instantiate() as GPUParticles2D
	if shard == null:
		return
	shard.global_position = to_global(map_to_local(anchor))
	shard.emitting = true
	get_tree().current_scene.add_child(shard)


func _update_minimap(cells: Array[Vector2i]) -> void:
	if gamemap == null or not is_instance_valid(gamemap.minimap):
		return
	gamemap.minimap.update_cellmap(cells)
