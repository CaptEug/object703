extends Block

signal drill_status_changed

const DRILL_DAMAGE_TYPE: StringName = &"KINETIC"
const MAX_QUERY_RESULTS := 256

@export_category("Drill")
@export var required_power := 100.0
@export var damage_per_second := 100.0
@export var drill_area: Area2D
@export_category("Drill Head")
@export var drill_head: Sprite2D
@export var head_scroll_speed := 64.0
@export var head_acceleration := 128.0
@export var head_scroll_period := 16.0

var supplied_power := 0.0
var storage_full := false

var _last_yield_item := ""
var _query_shape: Shape2D
var _query_shape_source: Node2D
var _head_origin_position := Vector2.ZERO
var _head_scroll_offset := 0.0
var _head_scroll_velocity := 0.0


func _ready() -> void:
	super()
	if drill_area == null:
		drill_area = get_node_or_null("Area2D") as Area2D
	if drill_head == null:
		drill_head = get_node_or_null("Mask/Sprite2D") as Sprite2D
	if drill_head != null:
		_head_origin_position = drill_head.position
	_prepare_query_shape()


func _physics_process(delta: float) -> void:
	_update_drill_head_motion(delta)
	_refresh_storage_availability()
	if not _is_activation_requested():
		return
	var power_ratio := get_power_ratio()
	if power_ratio <= 0.0:
		return
	var dmg := maxf(damage_per_second, 0.0) * power_ratio * delta
	if dmg <= 0.0:
		return
	for target: Dictionary in _collect_damage_targets():
		_damage_target(target, dmg)


func has_information_panel() -> bool:
	return true


func get_information_panel_key() -> StringName:
	return &"drill"


func get_power_demand() -> float:
	if not _is_activation_requested():
		return 0.0
	return maxf(required_power, 0.0)


func set_supplied_power(amount: float) -> void:
	var next_power := clampf(
		amount,
		0.0,
		maxf(required_power, 0.0)
	)
	if is_equal_approx(next_power, supplied_power):
		return
	supplied_power = next_power
	drill_status_changed.emit()


func get_power_ratio() -> float:
	if required_power <= 0.0:
		return 1.0
	return clampf(supplied_power / required_power, 0.0, 1.0)


func _is_activation_requested() -> bool:
	var current_assembly := get_assembly()
	return (
		current_assembly != null
		and current_assembly.has_method("get_fire_command")
		and bool(current_assembly.call("get_fire_command"))
	)


func _update_drill_head_motion(delta: float) -> void:
	if drill_head == null or head_scroll_period <= 0.0:
		return
	var target_velocity := 0.0
	if _is_activation_requested():
		target_velocity = head_scroll_speed * get_power_ratio()
	_head_scroll_velocity = move_toward(
		_head_scroll_velocity,
		target_velocity,
		maxf(head_acceleration, 0.0) * delta
	)
	_head_scroll_offset = wrapf(
		_head_scroll_offset + _head_scroll_velocity * delta,
		-head_scroll_period * 0.5,
		head_scroll_period * 0.5
	)
	drill_head.position = (
		_head_origin_position
		+ Vector2(_head_scroll_offset, 0.0)
	)


func _prepare_query_shape() -> void:
	_query_shape = null
	_query_shape_source = null
	if drill_area == null:
		return
	for child: Node in drill_area.get_children():
		if child is CollisionShape2D:
			var shape_node := child as CollisionShape2D
			if shape_node.disabled or shape_node.shape == null:
				continue
			_query_shape = shape_node.shape
			_query_shape_source = shape_node
			return
		if child is CollisionPolygon2D:
			var polygon_node := child as CollisionPolygon2D
			if polygon_node.disabled or polygon_node.polygon.size() < 3:
				continue
			var polygon_shape := ConvexPolygonShape2D.new()
			polygon_shape.points = polygon_node.polygon
			_query_shape = polygon_shape
			_query_shape_source = polygon_node
			return


func _collect_damage_targets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if (
		_query_shape == null
		or not is_instance_valid(_query_shape_source)
		or drill_area == null
	):
		return result
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _query_shape
	query.transform = _query_shape_source.global_transform
	query.collision_mask = drill_area.collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var current_assembly := get_assembly()
	if current_assembly is CollisionObject2D:
		query.exclude = [
			(current_assembly as CollisionObject2D).get_rid()
		]

	var targets_by_key := {}
	var hits := get_world_2d().direct_space_state.intersect_shape(
		query,
		MAX_QUERY_RESULTS
	)
	for hit: Dictionary in hits:
		var target := _resolve_damage_target(hit)
		if target.is_empty():
			continue
		targets_by_key[target["key"]] = target
	_collect_world_grid_targets(targets_by_key)
	for target: Dictionary in targets_by_key.values():
		result.append(target)
	return result


func _collect_world_grid_targets(targets_by_key: Dictionary) -> void:
	var world_polygon := _get_query_world_polygon()
	if world_polygon.size() < 3 or not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group(
		"world_block_layers"
	):
		var world_layer := node as WorldBlockLayer
		if world_layer == null:
			continue
		var local_polygon := PackedVector2Array()
		for world_point: Vector2 in world_polygon:
			local_polygon.append(world_layer.to_local(world_point))
		var bounds := Rect2(local_polygon[0], Vector2.ZERO)
		for local_point: Vector2 in local_polygon:
			bounds = bounds.expand(local_point)
		var minimum_cell := world_layer.local_to_map(
			bounds.position - Vector2.ONE
		)
		var maximum_cell := world_layer.local_to_map(
			bounds.end + Vector2.ONE
		)
		for y in range(minimum_cell.y, maximum_cell.y + 1):
			for x in range(minimum_cell.x, maximum_cell.x + 1):
				var cell := Vector2i(x, y)
				if (
					world_layer.get_block_id_at(cell)
					== BlockDB.INVALID_BLOCK_ID
					or not _polygon_overlaps_world_cell(
						local_polygon,
						world_layer,
						cell
					)
				):
					continue
				var target := _make_world_target(
					world_layer,
					cell
				)
				if not target.is_empty():
					targets_by_key[target["key"]] = target


func _get_query_world_polygon() -> PackedVector2Array:
	var result := PackedVector2Array()
	if (
		not _query_shape is ConvexPolygonShape2D
		or not is_instance_valid(_query_shape_source)
	):
		return result
	var polygon_shape := _query_shape as ConvexPolygonShape2D
	for local_point: Vector2 in polygon_shape.points:
		result.append(
			_query_shape_source.global_transform * local_point
		)
	return result


func _polygon_overlaps_world_cell(
	local_polygon: PackedVector2Array,
	world_layer: WorldBlockLayer,
	cell: Vector2i
) -> bool:
	var center := world_layer.map_to_local(cell)
	var half_size := Vector2.ONE * Globals.TILE_SIZE * 0.5
	var cell_polygon := PackedVector2Array([
		center + Vector2(-half_size.x, -half_size.y),
		center + Vector2(half_size.x, -half_size.y),
		center + Vector2(half_size.x, half_size.y),
		center + Vector2(-half_size.x, half_size.y),
	])
	if not Geometry2D.intersect_polygons(
		local_polygon,
		cell_polygon
	).is_empty():
		return true
	return Geometry2D.is_point_in_polygon(center, local_polygon)


func _resolve_damage_target(hit: Dictionary) -> Dictionary:
	var collider: Object = hit.get("collider", null)
	var shape_index := int(hit.get("shape", -1))
	if collider is Vehicle:
		var target_vehicle := collider as Vehicle
		if target_vehicle == get_assembly():
			return {}
		var target_block := _get_vehicle_block_for_shape(
			target_vehicle,
			shape_index
		)
		if target_block == null:
			return {}
		return {
			"key": "block:%d" % target_block.get_instance_id(),
			"host": target_vehicle,
			"cell": target_block.origin_cell,
			"block_id": target_block.block_id,
		}
	if collider is WorldBlockBody:
		var world_body := collider as WorldBlockBody
		if world_body.world_block_layer == null:
			return {}
		return _make_world_target(
			world_body.world_block_layer,
			world_body.anchor_cell
		)
	if collider is WorldBlockLayer:
		var world_layer := collider as WorldBlockLayer
		var body_rid: RID = hit.get("rid", RID())
		if not body_rid.is_valid():
			return {}
		var cell := world_layer.get_coords_for_body_rid(body_rid)
		return _make_world_target(world_layer, cell)
	return {}


func _get_vehicle_block_for_shape(
	target_vehicle: Vehicle,
	shape_index: int
) -> Block:
	if shape_index < 0:
		return null
	var owner_id := target_vehicle.shape_find_owner(shape_index)
	if owner_id < 0:
		return null
	var shape_owner := target_vehicle.shape_owner_get_owner(owner_id)
	for target_block: Block in target_vehicle.blocks:
		if target_block.collision == shape_owner:
			return target_block
	return null


func _make_world_target(
	world_layer: WorldBlockLayer,
	cell: Vector2i
) -> Dictionary:
	var anchor := world_layer.get_block_anchor(cell)
	if anchor == WorldBlockLayer.INVALID_CELL:
		return {}
	var target_id := world_layer.get_block_id_at(anchor)
	if target_id == BlockDB.INVALID_BLOCK_ID:
		return {}
	return {
		"key": "world:%d:%d:%d" % [
			world_layer.get_instance_id(),
			anchor.x,
			anchor.y,
		],
		"host": world_layer,
		"cell": anchor,
		"block_id": target_id,
	}


func _damage_target(target: Dictionary, dmg: float) -> void:
	var host: Object = target.get("host", null)
	if not is_instance_valid(host) or not host.has_method("damage_block_at"):
		return
	var cell: Vector2i = target.get("cell", Vector2i.ZERO)
	var target_id := int(
		target.get("block_id", BlockDB.INVALID_BLOCK_ID)
	)
	if (
		host.has_method("get_block_id_at")
		and int(host.call("get_block_id_at", cell)) != target_id
	):
		return
	var damage_result: Dictionary = host.call(
		"damage_block_at",
		cell,
		dmg,
		DRILL_DAMAGE_TYPE
	)
	if bool(damage_result.get("destroyed", false)):
		_store_mining_yield(target_id)


func _store_mining_yield(destroyed_block_id: int) -> void:
	var item_name := BlockDB.get_mining_yield(destroyed_block_id)
	if item_name.is_empty():
		return
	_last_yield_item = item_name
	var current_assembly := get_assembly()
	var received := 0
	if (
		current_assembly != null
		and current_assembly.has_method("receive_item")
	):
		received = int(current_assembly.call(
			"receive_item",
			self,
			item_name,
			1
		))
	_set_storage_full(received < 1)


func _refresh_storage_availability() -> void:
	if _last_yield_item.is_empty():
		return
	var current_assembly := get_assembly()
	var has_space := (
		current_assembly != null
		and current_assembly.has_method("can_receive_item")
		and bool(current_assembly.call(
			"can_receive_item",
			self,
			_last_yield_item,
			1
		))
	)
	_set_storage_full(not has_space)


func _set_storage_full(is_full: bool) -> void:
	if storage_full == is_full:
		return
	storage_full = is_full
	drill_status_changed.emit()
