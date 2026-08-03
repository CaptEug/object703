class_name BuildingSystem
extends Node

signal buildings_rebuilt(buildings: Array[Building])

const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
]

var world_blocks: WorldBlockLayer
var buildings: Array[Building] = []
var cell_to_building: Dictionary[Vector2i, Building] = {}
var anchor_to_building: Dictionary[Vector2i, Building] = {}

var _active_buildings: Array[Building] = []
var _pending_owner_by_anchor: Dictionary[Vector2i, StringName] = {}
var _pending_saved_metadata: Array[Dictionary] = []
var _bulk_edit_depth := 0
var _pending_full_rebuild := false
var _next_building_id := 1


func _ready() -> void:
	if get_parent() is WorldBlockLayer:
		setup(get_parent() as WorldBlockLayer)


func setup(layer: WorldBlockLayer) -> void:
	world_blocks = layer


func _physics_process(_delta: float) -> void:
	for building: Building in _active_buildings:
		building.update_functional_systems()


func begin_bulk_edit() -> void:
	_bulk_edit_depth += 1


func end_bulk_edit() -> void:
	_bulk_edit_depth = maxi(_bulk_edit_depth - 1, 0)
	if _bulk_edit_depth > 0:
		return
	if _pending_full_rebuild:
		rebuild_all()
	_pending_full_rebuild = false
	_apply_pending_saved_metadata()


func clear() -> void:
	buildings.clear()
	cell_to_building.clear()
	anchor_to_building.clear()
	_active_buildings.clear()
	_pending_owner_by_anchor.clear()
	_pending_saved_metadata.clear()
	_pending_full_rebuild = false
	_next_building_id = 1
	buildings_rebuilt.emit(buildings)


func get_building_at(cell: Vector2i) -> Building:
	return cell_to_building.get(cell, null)


func get_building_for_anchor(anchor: Vector2i) -> Building:
	return anchor_to_building.get(anchor, null)


func open_panel_at(cell: Vector2i) -> bool:
	var building := get_building_at(cell)
	if building == null:
		return false
	var panel := get_tree().get_first_node_in_group("building_panel")
	if panel == null or not panel.has_method("open_for_building"):
		return false
	var vehicle_editor := get_tree().get_first_node_in_group(
		"vehicle_editor"
	)
	if (
		vehicle_editor != null
		and vehicle_editor.has_method("close_vehicle_panel")
	):
		vehicle_editor.close_vehicle_panel()
	panel.open_for_building(building, world_blocks, cell)
	return true


func get_owner_for_anchor(
	anchor: Vector2i,
	fallback: StringName = &"player"
) -> StringName:
	var building := get_building_for_anchor(anchor)
	if building != null:
		return building.owner_id
	return _pending_owner_by_anchor.get(anchor, fallback)


func can_place_for_owner(
	occupied_cells: Array[Vector2i],
	owner_id: StringName
) -> bool:
	var adjacent_owners := {}
	for cell: Vector2i in occupied_cells:
		for direction: Vector2i in CARDINAL_DIRECTIONS:
			var building := get_building_at(cell + direction)
			if building != null:
				adjacent_owners[building.owner_id] = true
	if adjacent_owners.size() > 1:
		return false
	return adjacent_owners.is_empty() or adjacent_owners.has(owner_id)


func notify_constructed_changed(
	changed_cells: Array[Vector2i],
	owner_id: StringName = &"player"
) -> void:
	if world_blocks == null:
		return
	for cell: Vector2i in changed_cells:
		var anchor := world_blocks.get_block_anchor(cell)
		if anchor == WorldBlockLayer.INVALID_CELL:
			continue
		var state := world_blocks.get_block_state(anchor)
		if (
			not state.is_empty()
			and BlockDB.is_constructed(int(state["block_id"]))
		):
			_pending_owner_by_anchor[anchor] = owner_id
	if _bulk_edit_depth > 0:
		_pending_full_rebuild = true
		return
	_refresh_changed_region(changed_cells, owner_id)


func rebuild_all() -> void:
	if world_blocks == null:
		return
	var previous_by_anchor := anchor_to_building.duplicate()
	var candidates := {}
	for anchor: Vector2i in world_blocks.block_records:
		var state: Dictionary = world_blocks.block_records[anchor]
		if BlockDB.is_constructed(int(state["block_id"])):
			candidates[anchor] = true
	buildings.clear()
	cell_to_building.clear()
	anchor_to_building.clear()
	_active_buildings.clear()
	_build_components(candidates, previous_by_anchor, &"player")
	_pending_owner_by_anchor.clear()
	buildings_rebuilt.emit(buildings)


func _refresh_changed_region(
	changed_cells: Array[Vector2i],
	default_owner: StringName
) -> void:
	var affected := {}
	for cell: Vector2i in changed_cells:
		var building := get_building_at(cell)
		if building != null:
			affected[building] = true
		for direction: Vector2i in CARDINAL_DIRECTIONS:
			building = get_building_at(cell + direction)
			if building != null:
				affected[building] = true

	var candidates := {}
	var previous_by_anchor := {}
	for building: Building in affected:
		for anchor: Vector2i in building.block_anchors:
			candidates[anchor] = true
			previous_by_anchor[anchor] = building
		_remove_building(building)

	for cell: Vector2i in changed_cells:
		_add_current_anchor_candidate(cell, candidates)
		for direction: Vector2i in CARDINAL_DIRECTIONS:
			_add_current_anchor_candidate(
				cell + direction,
				candidates
			)

	_build_components(candidates, previous_by_anchor, default_owner)
	for anchor: Vector2i in candidates:
		_pending_owner_by_anchor.erase(anchor)
	buildings_rebuilt.emit(buildings)


func _add_current_anchor_candidate(
	cell: Vector2i,
	candidates: Dictionary
) -> void:
	var anchor := world_blocks.get_block_anchor(cell)
	if anchor == WorldBlockLayer.INVALID_CELL:
		return
	var state := world_blocks.get_block_state(anchor)
	if (
		not state.is_empty()
		and BlockDB.is_constructed(int(state["block_id"]))
	):
		candidates[anchor] = true


func _remove_building(building: Building) -> void:
	buildings.erase(building)
	_active_buildings.erase(building)
	for anchor: Vector2i in building.block_anchors:
		anchor_to_building.erase(anchor)
	for cell: Vector2i in building.occupied_cells:
		cell_to_building.erase(cell)


func _build_components(
	candidate_anchors: Dictionary,
	previous_by_anchor: Dictionary,
	default_owner: StringName
) -> void:
	var unvisited := {}
	for anchor: Vector2i in candidate_anchors:
		var state: Dictionary = world_blocks.block_records.get(
			anchor,
			{}
		)
		if (
			not state.is_empty()
			and BlockDB.is_constructed(int(state["block_id"]))
		):
			unvisited[anchor] = true

	var reused_ids := {}
	while not unvisited.is_empty():
		var start := Vector2i.ZERO
		for candidate: Vector2i in unvisited:
			start = candidate
			break
		var component: Array[Vector2i] = []
		var stack: Array[Vector2i] = [start]
		while not stack.is_empty():
			var anchor: Vector2i = stack.pop_back()
			if not unvisited.has(anchor):
				continue
			unvisited.erase(anchor)
			component.append(anchor)
			for occupied_cell: Vector2i in (
				world_blocks.get_record_occupied_cells(anchor)
			):
				for direction: Vector2i in CARDINAL_DIRECTIONS:
					var neighbor := world_blocks.get_block_anchor(
						occupied_cell + direction
					)
					if unvisited.has(neighbor):
						stack.append(neighbor)
		_create_building(
			component,
			previous_by_anchor,
			default_owner,
			reused_ids
		)


func _create_building(
	component: Array[Vector2i],
	previous_by_anchor: Dictionary,
	default_owner: StringName,
	reused_ids: Dictionary
) -> void:
	var inherited: Building
	for anchor: Vector2i in component:
		var candidate := previous_by_anchor.get(anchor, null) as Building
		if candidate != null:
			inherited = candidate
			break

	var building := Building.new()
	building.world_block_layer = world_blocks
	if inherited != null:
		building.owner_id = inherited.owner_id
		building.building_name = inherited.building_name
		if not reused_ids.has(inherited.building_id):
			building.building_id = inherited.building_id
			reused_ids[inherited.building_id] = true
	else:
		building.owner_id = default_owner
		for anchor: Vector2i in component:
			if _pending_owner_by_anchor.has(anchor):
				building.owner_id = _pending_owner_by_anchor[anchor]
				break

	if building.building_id <= 0:
		building.building_id = _allocate_building_id()
	else:
		_next_building_id = maxi(
			_next_building_id,
			building.building_id + 1
		)

	building.block_anchors = component
	for anchor: Vector2i in component:
		anchor_to_building[anchor] = building
		for cell: Vector2i in (
			world_blocks.get_record_occupied_cells(anchor)
		):
			building.occupied_cells.append(cell)
			cell_to_building[cell] = building
		var functional_block := world_blocks.functional_nodes.get(
			anchor,
			null
		) as Block
		if functional_block != null:
			building.functional_blocks.append(functional_block)

	var preferred_control: ControlBlock
	if (
		inherited != null
		and is_instance_valid(inherited.active_control_block)
		and building.functional_blocks.has(
			inherited.active_control_block
		)
	):
		preferred_control = inherited.active_control_block
	building.refresh_functional_state(preferred_control)
	if building.block_assembly.power_consumers.is_empty():
		for engine: PowerPack in building.block_assembly.engines:
			engine.power_target = 0.0
	elif building.block_assembly.engines.is_empty():
		for consumer: Block in building.block_assembly.power_consumers:
			consumer.set_supplied_power(0.0)
	else:
		_active_buildings.append(building)
	buildings.append(building)


func _allocate_building_id() -> int:
	var result := _next_building_id
	_next_building_id += 1
	return result


func get_constructed_save_data() -> Array:
	var result: Array = []
	for building: Building in buildings:
		if building.block_anchors.is_empty():
			continue
		var origin := building.block_anchors[0]
		for anchor: Vector2i in building.block_anchors:
			origin.x = mini(origin.x, anchor.x)
			origin.y = mini(origin.y, anchor.y)
		var anchors := building.block_anchors.duplicate()
		anchors.sort_custom(
			func(a: Vector2i, b: Vector2i) -> bool:
				return a.y < b.y or (a.y == b.y and a.x < b.x)
		)
		var block_data: Array = []
		for anchor: Vector2i in anchors:
			var state: Dictionary = world_blocks.block_records.get(
				anchor,
				{}
			)
			if state.is_empty():
				continue
			var block_id := int(state["block_id"])
			var size: Vector2i = state.get(
				"size",
				BlockDB.get_size(block_id)
			)
			var max_hp := world_blocks.get_state_max_hp(
				block_id,
				size
			)
			var health := (
				0
				if max_hp <= 0.0
				else clampi(
					roundi(float(state["hp"]) / max_hp * 65535.0),
					0,
					65535
				)
			)
			var record: Array = [
				block_id,
				anchor.x - origin.x,
				anchor.y - origin.y,
				int(state.get("rotation", 0)),
				health,
			]
			var extra := {}
			if size != BlockDB.get_size(block_id):
				extra["size"] = [size.x, size.y]
			var functional := world_blocks.functional_nodes.get(
				anchor,
				null
			) as Block
			if functional != null:
				var saved_state := functional.get_save_state()
				if not saved_state.is_empty():
					extra["state"] = saved_state
			if not extra.is_empty():
				record.append(extra)
			block_data.append(record)

		var building_record := {
			"building_id": building.building_id,
			"building_name": building.building_name,
			"owner_name": String(building.owner_id),
			"origin": [origin.x, origin.y],
			"blocks": block_data,
		}
		if is_instance_valid(building.active_control_block):
			var control_anchor := building.active_control_block.origin_cell
			building_record["active_control"] = [
				control_anchor.x - origin.x,
				control_anchor.y - origin.y,
			]
		result.append(building_record)
	return result


func restore_constructed_save_data(records: Array) -> void:
	if world_blocks == null:
		return
	for value: Variant in records:
		if not value is Dictionary:
			continue
		var building_record := value as Dictionary
		var origin_value: Variant = building_record.get("origin")
		var blocks_value: Variant = building_record.get("blocks")
		if (
			not origin_value is Array
			or (origin_value as Array).size() != 2
			or not blocks_value is Array
		):
			continue
		var origin := Vector2i(
			int((origin_value as Array)[0]),
			int((origin_value as Array)[1])
		)
		var owner_id := StringName(
			str(building_record.get("owner_name", "player"))
		)
		var representative := WorldBlockLayer.INVALID_CELL
		for block_value: Variant in blocks_value:
			if not block_value is Array:
				continue
			var record := block_value as Array
			if record.size() < 5:
				continue
			var block_id := int(record[0])
			if (
				not BlockDB.has_block(block_id)
				or not BlockDB.is_constructed(block_id)
			):
				continue
			var anchor := origin + Vector2i(
				int(record[1]),
				int(record[2])
			)
			var rotation := int(record[3])
			var health := clampi(int(record[4]), 0, 65535)
			var size := BlockDB.get_size(block_id)
			var functional_state := {}
			if record.size() >= 6 and record[5] is Dictionary:
				var extra := record[5] as Dictionary
				var size_value: Variant = extra.get("size")
				if size_value is Array and (size_value as Array).size() == 2:
					size = Vector2i(
						maxi(int((size_value as Array)[0]), 1),
						maxi(int((size_value as Array)[1]), 1)
					)
				if extra.get("state") is Dictionary:
					functional_state = extra["state"]
			var max_hp := world_blocks.get_state_max_hp(block_id, size)
			var hp := max_hp * float(health) / 65535.0
			if world_blocks.restore_constructed_block(
				block_id,
				anchor,
				rotation,
				hp,
				size,
				functional_state,
				owner_id
			):
				if representative == WorldBlockLayer.INVALID_CELL:
					representative = anchor
		if representative == WorldBlockLayer.INVALID_CELL:
			continue
		var metadata := building_record.duplicate(true)
		metadata["representative"] = [
			representative.x,
			representative.y,
		]
		_pending_saved_metadata.append(metadata)
	if _bulk_edit_depth == 0:
		_apply_pending_saved_metadata()


func _apply_pending_saved_metadata() -> void:
	if _pending_saved_metadata.is_empty():
		return
	for record: Dictionary in _pending_saved_metadata:
		var representative_value: Variant = record.get("representative")
		if (
			not representative_value is Array
			or (representative_value as Array).size() != 2
		):
			continue
		var building := get_building_at(Vector2i(
			int((representative_value as Array)[0]),
			int((representative_value as Array)[1])
		))
		if building == null:
			continue
		building.building_id = maxi(
			int(record.get("building_id", building.building_id)),
			1
		)
		_next_building_id = maxi(
			_next_building_id,
			building.building_id + 1
		)
		building.owner_id = StringName(
			str(record.get("owner_name", "player"))
		)
		building.building_name = str(
			record.get("building_name", "New Building")
		)
		var active_value: Variant = record.get("active_control")
		var origin_value: Variant = record.get("origin")
		if (
			active_value is Array
			and (active_value as Array).size() == 2
			and origin_value is Array
			and (origin_value as Array).size() == 2
		):
			var active_anchor := Vector2i(
				int((origin_value as Array)[0])
					+ int((active_value as Array)[0]),
				int((origin_value as Array)[1])
					+ int((active_value as Array)[1])
			)
			var control := world_blocks.functional_nodes.get(
				active_anchor,
				null
			) as ControlBlock
			if control != null:
				building.set_active_control_block(control)
	_pending_saved_metadata.clear()
	buildings_rebuilt.emit(buildings)
