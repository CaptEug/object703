class_name StructureGenerator
extends RefCounted

const STARTER_WORKSHOP_NAME := "Starter Vehicle Workshop"
const WORKSHOP_BLOCK_NAME := "Workshop"
const WORKSHOP_ROWS := 3
const WORKSHOP_COLUMNS := 4
const STRUCTURE_CLEARANCE := 1


static func generate_default_structures(gamemap: GameMap) -> Dictionary:
	if not is_instance_valid(gamemap):
		return _error("Structure generation has no map.")
	var workshop_id := BlockDB.get_id_for_name(WORKSHOP_BLOCK_NAME)
	if (
		workshop_id == BlockDB.INVALID_BLOCK_ID
		or not BlockDB.is_constructed(workshop_id)
		or not BlockDB.can_place_on(workshop_id, BlockDB.HOST_WORLD)
	):
		return _error("The Workshop block is unavailable for world structures.")

	var unit_size := BlockDB.get_size(workshop_id)
	var anchors: Array[Vector2i] = []
	for row in range(WORKSHOP_ROWS):
		for column in range(WORKSHOP_COLUMNS):
			anchors.append(Vector2i(
				column * unit_size.x,
				row * unit_size.y
			))
	var footprint := Vector2i(
		WORKSHOP_COLUMNS * unit_size.x,
		WORKSHOP_ROWS * unit_size.y
	)
	var site := _find_near_center_site(
		gamemap,
		workshop_id,
		anchors,
		footprint
	)
	if site == WorldBlockLayer.INVALID_CELL:
		return _error(
			"No legitimate site was found for the starter vehicle workshop."
		)
	return _place_structure(
		gamemap,
		workshop_id,
		anchors,
		site,
		STARTER_WORKSHOP_NAME
	)


static func _find_near_center_site(
	gamemap: GameMap,
	block_id: int,
	anchors: Array[Vector2i],
	footprint: Vector2i
) -> Vector2i:
	var centered_origin := Vector2i(
		-footprint.x / 2,
		-footprint.y / 2
	)
	var maximum_radius := maxi(gamemap.world_width, gamemap.world_height)
	var quarter_turns := posmod(hash(gamemap.world_seed), 4)
	for radius in range(maximum_radius + 1):
		var offsets := _get_ring_offsets(radius)
		for offset: Vector2i in offsets:
			var rotated_offset := offset
			for turn in range(quarter_turns):
				rotated_offset = Vector2i(
					-rotated_offset.y,
					rotated_offset.x
				)
			var candidate := centered_origin + rotated_offset
			if _is_legitimate_site(
				gamemap,
				block_id,
				anchors,
				candidate,
				footprint
			):
				return candidate
	return WorldBlockLayer.INVALID_CELL


static func _get_ring_offsets(radius: int) -> Array[Vector2i]:
	if radius <= 0:
		return [Vector2i.ZERO]
	var result: Array[Vector2i] = []
	for x in range(-radius, radius + 1):
		result.append(Vector2i(x, -radius))
	for y in range(-radius + 1, radius + 1):
		result.append(Vector2i(radius, y))
	for x in range(radius - 1, -radius - 1, -1):
		result.append(Vector2i(x, radius))
	for y in range(radius - 1, -radius, -1):
		result.append(Vector2i(-radius, y))
	return result


static func _is_legitimate_site(
	gamemap: GameMap,
	block_id: int,
	anchors: Array[Vector2i],
	origin: Vector2i,
	footprint: Vector2i
) -> bool:
	var clearance := Rect2i(
		origin - Vector2i.ONE * STRUCTURE_CLEARANCE,
		footprint + Vector2i.ONE * STRUCTURE_CLEARANCE * 2
	)
	if not gamemap.world_bounds.encloses(clearance):
		return false
	for y in range(clearance.position.y, clearance.end.y):
		for x in range(clearance.position.x, clearance.end.x):
			var cell := Vector2i(x, y)
			if (
				gamemap.world_blocks.get_block_id_at(cell)
				!= BlockDB.INVALID_BLOCK_ID
				or gamemap.liquid.get_block_id_at(cell)
				!= BlockDB.INVALID_BLOCK_ID
			):
				return false
	for y in range(origin.y, origin.y + footprint.y):
		for x in range(origin.x, origin.x + footprint.x):
			if (
				gamemap.ground.get_ground_block_id_at(Vector2i(x, y))
				== BlockDB.INVALID_BLOCK_ID
			):
				return false
	for anchor_offset: Vector2i in anchors:
		if not gamemap.world_blocks.can_place_block(
			block_id,
			origin + anchor_offset,
			0,
			&"player"
		):
			return false
	return true


static func _place_structure(
	gamemap: GameMap,
	block_id: int,
	anchors: Array[Vector2i],
	origin: Vector2i,
	structure_name: String
) -> Dictionary:
	gamemap.world_blocks.begin_bulk_edit()
	var success := true
	for anchor_offset: Vector2i in anchors:
		if not gamemap.world_blocks.place_block(
			block_id,
			origin + anchor_offset,
			0,
			-1.0,
			&"player"
		):
			success = false
			break
	if not success:
		_erase_structure_footprint(gamemap.world_blocks, origin, anchors, block_id)
	gamemap.world_blocks.end_bulk_edit()
	if not success:
		return _error("Starter workshop placement failed and was rolled back.")

	var building := gamemap.world_blocks.get_building_at(origin)
	if building == null or not building.is_vehicle_workshop():
		_erase_structure_footprint(gamemap.world_blocks, origin, anchors, block_id)
		return _error("Starter workshop did not form a vehicle workshop building.")
	building.building_name = structure_name
	return {
		"ok": true,
		"origin": origin,
		"building_id": building.building_id,
	}


static func _erase_structure_footprint(
	world_blocks: WorldBlockLayer,
	origin: Vector2i,
	anchors: Array[Vector2i],
	block_id: int
) -> void:
	var unit_size := BlockDB.get_size(block_id)
	var destroyed := {}
	for anchor_offset: Vector2i in anchors:
		for y in range(unit_size.y):
			for x in range(unit_size.x):
				var cell := origin + anchor_offset + Vector2i(x, y)
				var anchor := world_blocks.get_block_anchor(cell)
				if (
					anchor != WorldBlockLayer.INVALID_CELL
					and not destroyed.has(anchor)
				):
					destroyed[anchor] = true
					world_blocks.destroy_block_at(anchor, false)


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
