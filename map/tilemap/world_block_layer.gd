class_name WorldBlockLayer
extends TileMapLayer

signal block_placed(anchor: Vector2i, block_id: int)
signal block_damaged(anchor: Vector2i, result: Dictionary)
signal block_destroyed(anchor: Vector2i, block_id: int)
signal buildings_rebuilt(buildings: Array[Building])

const INVALID_CELL := Vector2i(-2147483648, -2147483648)
const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
]

# One record per placed block, keyed by its anchor. Every occupied grid cell
# maps back to that anchor, allowing multi-cell blocks to share one HP value.
var block_records: Dictionary[Vector2i, Dictionary] = {}
var cell_occupancy: Dictionary[Vector2i, Vector2i] = {}
var functional_nodes: Dictionary[Vector2i, Block] = {}
var buildings: Array[Building] = []
var cell_to_building: Dictionary[Vector2i, Building] = {}

var _bulk_edit_depth := 0
var _pending_visual_cells: Dictionary = {}
var _pending_building_rebuild := false
var _pending_owner_by_anchor: Dictionary = {}

@onready var gamemap: GameMap = get_parent()
@onready var functional_root: Node2D = get_node_or_null(
	"FunctionalBlocks"
) as Node2D


func _ready() -> void:
	add_to_group("world_block_layers")
	if functional_root == null:
		functional_root = Node2D.new()
		functional_root.name = "FunctionalBlocks"
		add_child(functional_root)


func begin_bulk_edit() -> void:
	_bulk_edit_depth += 1


func end_bulk_edit() -> void:
	_bulk_edit_depth = maxi(_bulk_edit_depth - 1, 0)
	if _bulk_edit_depth > 0:
		return
	_flush_visual_updates()
	if _pending_building_rebuild:
		rebuild_buildings()
	_pending_building_rebuild = false


func initialize_from_tilemap() -> void:
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
	rebuild_buildings()


# Compatibility with the previous world generation call.
func init_layerdata() -> void:
	initialize_from_tilemap()


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


func get_building_at(cell: Vector2i) -> Building:
	return cell_to_building.get(cell, null)


func get_assembly_at(cell: Vector2i) -> Object:
	return get_building_at(cell)


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
	for cell: Vector2i in _get_occupied_cells(
		block_id,
		anchor,
		normalized_rotation
	):
		if cell_occupancy.has(cell):
			return false

	if not BlockDB.is_constructed(block_id):
		return true
	var adjacent_owners := {}
	for cell: Vector2i in _get_occupied_cells(
		block_id,
		anchor,
		normalized_rotation
	):
		for direction: Vector2i in CARDINAL_DIRECTIONS:
			var building := get_building_at(cell + direction)
			if building != null:
				adjacent_owners[building.owner_id] = true
	if adjacent_owners.size() > 1:
		return false
	if (
		adjacent_owners.size() == 1
		and not adjacent_owners.has(owner_id)
	):
		return false
	return true


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

	if BlockDB.is_constructed(block_id):
		_pending_owner_by_anchor[anchor] = owner_id
		_request_building_rebuild()
	_queue_visual_refresh(_get_occupied_cells(
		block_id,
		anchor,
		normalized_rotation
	))
	block_placed.emit(anchor, block_id)
	return true


func damage_block_at(
	cell: Vector2i,
	amount: float,
	damage_type: StringName
) -> Dictionary:
	var anchor := get_block_anchor(cell)
	if anchor == INVALID_CELL:
		return BlockDamage.miss()
	var state: Dictionary = block_records[anchor]
	var block_id := int(state["block_id"])
	var result := BlockDamage.calculate(
		block_id,
		float(state["hp"]),
		amount,
		damage_type
	)
	if not result["hit"]:
		return result
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
	return result


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


func destroy_block_at(cell: Vector2i) -> bool:
	var anchor := get_block_anchor(cell)
	if anchor == INVALID_CELL:
		return false
	var state: Dictionary = block_records.get(anchor, {})
	if state.is_empty():
		return false
	var block_id := int(state["block_id"])
	var occupied_cells := _get_occupied_cells(
		block_id,
		anchor,
		int(state.get("rotation", 0))
	)
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
		_request_building_rebuild()
	_update_minimap(occupied_cells)
	block_destroyed.emit(anchor, block_id)
	return true


func destroy_tile(cell: Vector2i) -> bool:
	return destroy_block_at(cell)


func rebuild_buildings() -> void:
	var previous_cell_map := cell_to_building.duplicate()
	var unvisited := {}
	for anchor: Vector2i in block_records:
		if BlockDB.is_constructed(
			int(block_records[anchor]["block_id"])
		):
			unvisited[anchor] = true

	var rebuilt: Array[Building] = []
	var rebuilt_cell_map: Dictionary[Vector2i, Building] = {}
	while not unvisited.is_empty():
		var start: Vector2i = unvisited.keys()[0]
		var component: Array[Vector2i] = []
		var queue: Array[Vector2i] = [start]
		while not queue.is_empty():
			var anchor: Vector2i = queue.pop_front()
			if not unvisited.has(anchor):
				continue
			unvisited.erase(anchor)
			component.append(anchor)
			var state: Dictionary = block_records[anchor]
			for occupied_cell: Vector2i in _get_occupied_cells(
				int(state["block_id"]),
				anchor,
				int(state.get("rotation", 0))
			):
				for direction: Vector2i in CARDINAL_DIRECTIONS:
					var neighbor_anchor := get_block_anchor(
						occupied_cell + direction
					)
					if (
						neighbor_anchor != INVALID_CELL
						and unvisited.has(neighbor_anchor)
					):
						queue.append(neighbor_anchor)

		var building: Building = Building.new()
		var inherited: Building
		for anchor: Vector2i in component:
			var previous: Building = previous_cell_map.get(anchor, null)
			if previous != null:
				inherited = previous
				break
		if inherited != null:
			building.owner_id = inherited.owner_id
			building.building_name = inherited.building_name
		else:
			for anchor: Vector2i in component:
				if _pending_owner_by_anchor.has(anchor):
					building.owner_id = _pending_owner_by_anchor[anchor]
					break

		building.block_anchors = component
		for anchor: Vector2i in component:
			var state: Dictionary = block_records[anchor]
			for occupied_cell: Vector2i in _get_occupied_cells(
				int(state["block_id"]),
				anchor,
				int(state.get("rotation", 0))
			):
				if not building.occupied_cells.has(occupied_cell):
					building.occupied_cells.append(occupied_cell)
				rebuilt_cell_map[occupied_cell] = building
			var functional_block: Block = functional_nodes.get(
				anchor,
				null
			)
			if functional_block != null:
				building.functional_blocks.append(functional_block)
		rebuilt.append(building)

	buildings = rebuilt
	cell_to_building = rebuilt_cell_map
	_pending_owner_by_anchor.clear()
	buildings_rebuilt.emit(buildings)


func get_building_save_data() -> Array:
	var result: Array = []
	for building: Building in buildings:
		if building.block_anchors.is_empty():
			continue
		var anchor := building.block_anchors[0]
		result.append({
			"anchor": [anchor.x, anchor.y],
			"owner_name": String(building.owner_id),
			"building_name": building.building_name,
		})
	return result


func apply_building_save_data(records: Array) -> void:
	for value: Variant in records:
		if not value is Dictionary:
			continue
		var record := value as Dictionary
		var anchor_value: Variant = record.get("anchor")
		if (
			not anchor_value is Array
			or (anchor_value as Array).size() != 2
		):
			continue
		var anchor := Vector2i(
			int((anchor_value as Array)[0]),
			int((anchor_value as Array)[1])
		)
		var building := get_building_at(anchor)
		if building == null:
			continue
		building.owner_id = StringName(
			str(record.get("owner_name", "player"))
		)
		building.building_name = str(
			record.get("building_name", "New Building")
		)


func save_chunk(chunk_x: int, chunk_y: int) -> PackedByteArray:
	const CHUNK_SIZE := 32
	var bytes := PackedByteArray()
	for ly in range(CHUNK_SIZE):
		for lx in range(CHUNK_SIZE):
			var cell := Vector2i(
				chunk_x * CHUNK_SIZE + lx,
				chunk_y * CHUNK_SIZE + ly
			)
			var state: Dictionary = block_records.get(cell, {})
			var offset := bytes.size()
			bytes.resize(offset + 5)
			if state.is_empty():
				bytes.encode_u16(offset, 0)
				bytes.encode_u16(offset + 2, 0)
				bytes[offset + 4] = 0
				continue
			bytes.encode_u16(offset, int(state["block_id"]))
			bytes.encode_u16(
				offset + 2,
				clampi(roundi(float(state["hp"])), 0, 65535)
			)
			bytes[offset + 4] = int(state.get("rotation", 0))
	return bytes


func load_chunk(
	chunk_x: int,
	chunk_y: int,
	bytes: PackedByteArray,
	chunk_size: int
) -> void:
	var index := 0
	for ly in range(chunk_size):
		for lx in range(chunk_size):
			var block_id := bytes.decode_u16(index)
			var hp := bytes.decode_u16(index + 2)
			var rotation_index := bytes.decode_u8(index + 4)
			index += 5
			if block_id == 0:
				continue
			if not BlockDB.has_block(block_id):
				push_error("Unknown saved block ID %d." % block_id)
				continue
			var cell := Vector2i(
				chunk_x * chunk_size + lx,
				chunk_y * chunk_size + ly
			)
			place_block(
				block_id,
				cell,
				rotation_index,
				float(hp)
			)


func load_legacy_wall_chunk(
	chunk_x: int,
	chunk_y: int,
	bytes: PackedByteArray,
	chunk_size: int,
	liquid_layer: LiquidLayer
) -> void:
	var index := 0
	for ly in range(chunk_size):
		for lx in range(chunk_size):
			var tile_id := bytes.decode_u8(index)
			var data := bytes.decode_u16(index + 1)
			index += 3
			if tile_id == 0:
				continue
			var cell := Vector2i(
				chunk_x * chunk_size + lx,
				chunk_y * chunk_size + ly
			)
			var block_id := BlockDB.get_legacy_world_block_id(tile_id)
			if block_id != BlockDB.INVALID_BLOCK_ID:
				place_block(block_id, cell, 0, float(data))
			else:
				var liquid_block_id := (
					BlockDB.get_legacy_liquid_block_id(tile_id)
				)
				if liquid_block_id == BlockDB.INVALID_BLOCK_ID:
					continue
				liquid_layer.set_liquid_cell(
					cell,
					liquid_block_id,
					float(data),
					false
				)


func _register_block_state(
	anchor: Vector2i,
	block_id: int,
	rotation_index: int,
	hp: float
) -> void:
	block_records[anchor] = {
		"block_id": block_id,
		"hp": hp,
		"rotation": rotation_index,
	}
	for cell: Vector2i in _get_occupied_cells(
		block_id,
		anchor,
		rotation_index
	):
		cell_occupancy[cell] = anchor


func _get_occupied_cells(
	block_id: int,
	anchor: Vector2i,
	rotation_index: int
) -> Array[Vector2i]:
	var block_size := BlockDB.get_size(block_id)
	if rotation_index % 2 != 0:
		block_size = Vector2i(block_size.y, block_size.x)
	var cells: Array[Vector2i] = []
	for y in range(block_size.y):
		for x in range(block_size.x):
			cells.append(anchor + Vector2i(x, y))
	return cells


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


func _request_building_rebuild() -> void:
	_pending_building_rebuild = true
	if _bulk_edit_depth == 0:
		rebuild_buildings()
		_pending_building_rebuild = false


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
