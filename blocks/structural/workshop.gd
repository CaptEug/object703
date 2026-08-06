class_name MaintenanceBayBlock
extends ExpandableBlock

signal docked_vehicle_changed(vehicle: Vehicle)
signal front_direction_changed(direction: int)

enum FrontDirection {
	UP,
	RIGHT,
	DOWN,
	LEFT,
}

const CONTAINMENT_EPSILON := 0.05
const CELL_CORNERS: Array[Vector2] = [
	Vector2.ZERO,
	Vector2.RIGHT,
	Vector2.ONE,
	Vector2.DOWN,
]

var candidate_vehicles: Array[Vehicle] = []
var vehicle_front: FrontDirection = FrontDirection.UP
var _docked_vehicle: Vehicle

@onready var docking_area := $DockingArea as Area2D
@onready var docking_shape := (
	$DockingArea/CollisionShape2D as CollisionShape2D
)


func _ready() -> void:
	super()
	if not docking_area.body_entered.is_connected(
		_on_docking_body_entered
	):
		docking_area.body_entered.connect(_on_docking_body_entered)
	if not docking_area.body_exited.is_connected(
		_on_docking_body_exited
	):
		docking_area.body_exited.connect(_on_docking_body_exited)
	var world_layer := block_host as WorldBlockLayer
	docking_area.monitoring = (
		world_layer != null
		and get_parent() == world_layer.functional_root
	)
	docking_area.monitorable = false
	_on_union_geometry_changed()
	_refresh_docked_vehicle()


func _physics_process(_delta: float) -> void:
	_refresh_docked_vehicle()


func has_information_panel() -> bool:
	return true


func get_information_panel_key() -> StringName:
	return &"maintenance_bay"


func get_save_state() -> Dictionary:
	return {"vehicle_front": int(vehicle_front)}


func apply_save_state(state: Dictionary) -> void:
	set_vehicle_front(int(state.get("vehicle_front", FrontDirection.UP)))


func set_vehicle_front(direction: int) -> void:
	var normalized: FrontDirection = wrapi(direction, 0, 4)
	if vehicle_front == normalized:
		return
	vehicle_front = normalized
	queue_redraw()
	front_direction_changed.emit(int(vehicle_front))


func get_vehicle_front_rotation() -> float:
	return global_rotation + float(vehicle_front) * PI * 0.5


func get_editor_front_rotation(target: Vehicle = null) -> float:
	if is_instance_valid(target):
		return target.global_rotation
	return get_vehicle_front_rotation()


func refresh_union_visual() -> void:
	if _union_source_atlas == null:
		return
	if (
		_union_visual_root == null
		or not is_instance_valid(_union_visual_root)
	):
		_union_visual_root = get_node_or_null("UnionVisual") as Node2D
		if _union_visual_root == null:
			_union_visual_root = Node2D.new()
			_union_visual_root.name = "UnionVisual"
			add_child(_union_visual_root)
	var base_size := BlockDB.get_size(block_id)
	BlockVisualSystem.apply_rectangle_merge_to_node(
		_union_visual_root,
		_union_source_atlas,
		_union_atlas_origin,
		Vector2i(size.x / base_size.x, size.y / base_size.y),
		TILE_SIZE * base_size.x
	)


func _merge_union_data(members: Array) -> void:
	var direction_source: MaintenanceBayBlock = self
	var largest_area := size.x * size.y
	var merged_candidates: Array[Vehicle] = []
	var merged_docked_vehicle: Vehicle
	var docked_source_area := -1
	for value: Variant in members:
		var member := value as MaintenanceBayBlock
		if member == null:
			continue
		var member_area := member.size.x * member.size.y
		if member_area > largest_area:
			largest_area = member_area
			direction_source = member
		if (
			is_instance_valid(member._docked_vehicle)
			and member_area > docked_source_area
		):
			docked_source_area = member_area
			merged_docked_vehicle = member._docked_vehicle
		for target: Vehicle in member.candidate_vehicles:
			if is_instance_valid(target) and not merged_candidates.has(target):
				merged_candidates.append(target)
	vehicle_front = direction_source.vehicle_front
	candidate_vehicles = merged_candidates
	_docked_vehicle = merged_docked_vehicle


func _on_union_geometry_changed() -> void:
	var shape_node := docking_shape
	if not is_instance_valid(shape_node):
		shape_node = get_node_or_null(
			"DockingArea/CollisionShape2D"
		) as CollisionShape2D
	if shape_node != null:
		var rectangle := shape_node.shape as RectangleShape2D
		if rectangle != null:
			rectangle.size = Vector2(get_rotated_size()) * TILE_SIZE
	queue_redraw()


func get_docked_vehicle() -> Vehicle:
	_refresh_docked_vehicle()
	return _docked_vehicle if is_instance_valid(_docked_vehicle) else null


func track_candidate_vehicle(target: Vehicle) -> void:
	if (
		is_instance_valid(target)
		and not candidate_vehicles.has(target)
	):
		candidate_vehicles.append(target)
	_refresh_docked_vehicle()


func untrack_candidate_vehicle(target: Vehicle) -> void:
	if is_instance_valid(target):
		candidate_vehicles.erase(target)
	_refresh_docked_vehicle()


func is_vehicle_fully_inside(target: Vehicle) -> bool:
	if not is_instance_valid(target) or target.blocks.is_empty():
		return false
	return is_vehicle_layout_inside(target)


func is_vehicle_layout_inside(
	target: Vehicle,
	extra_block: Block = null
) -> bool:
	if not is_instance_valid(target):
		return false
	var half_size := Vector2(get_rotated_size()) * TILE_SIZE * 0.5
	for block: Block in target.blocks:
		if not _is_block_inside(target, block, half_size):
			return false
	if is_instance_valid(extra_block):
		if not _is_block_inside(target, extra_block, half_size):
			return false
	return true


func can_host_vehicle(target: Vehicle, owner_id: StringName) -> bool:
	return (
		is_instance_valid(target)
		and target.owner_id == owner_id
		and is_vehicle_fully_inside(target)
	)


func get_center_world_position() -> Vector2:
	return global_position


func get_aligned_vehicle_transform(
	footprint_size: Vector2i,
	vehicle_rotation: float
) -> Transform2D:
	if footprint_size.x <= 0 or footprint_size.y <= 0:
		return Transform2D(vehicle_rotation, global_position)
	var quarter_value := (
		(vehicle_rotation - global_rotation) / (PI * 0.5)
	)
	var quarter_turn := wrapi(roundi(quarter_value), 0, 4)
	var snapped_rotation := (
		global_rotation + float(quarter_turn) * PI * 0.5
	)
	if absf(wrapf(
		vehicle_rotation - snapped_rotation,
		-PI,
		PI
	)) > 0.001:
		return _get_nearest_grid_center_transform(
			footprint_size,
			vehicle_rotation
		)

	var rotated_bounds := _get_rotated_footprint_bounds(
		footprint_size,
		quarter_turn
	)
	var bay_size := get_rotated_size()
	var bay_minimum := -Vector2i(
		bay_size.x / 2,
		bay_size.y / 2
	)
	var remaining := bay_size - rotated_bounds.size
	var margin_before := Vector2i(
		floori(float(remaining.x) * 0.5),
		floori(float(remaining.y) * 0.5)
	)
	var origin_cell := (
		bay_minimum
		+ margin_before
		- rotated_bounds.position
	)
	return Transform2D(
		vehicle_rotation,
		to_global(Vector2(origin_cell) * TILE_SIZE)
	)


func _get_nearest_grid_center_transform(
	footprint_size: Vector2i,
	vehicle_rotation: float
) -> Transform2D:
	var relative_rotation := vehicle_rotation - global_rotation
	var relative_transform := Transform2D(
		relative_rotation,
		Vector2.ZERO
	)
	var center_offset := relative_transform.basis_xform(
		Vector2(footprint_size) * TILE_SIZE * 0.5
	)
	var desired_origin := -center_offset
	var snapped_origin := Vector2(
		roundi(desired_origin.x / TILE_SIZE) * TILE_SIZE,
		roundi(desired_origin.y / TILE_SIZE) * TILE_SIZE
	)
	return Transform2D(
		vehicle_rotation,
		to_global(snapped_origin)
	)


func _get_rotated_footprint_bounds(
	footprint_size: Vector2i,
	quarter_turn: int
) -> Rect2i:
	match wrapi(quarter_turn, 0, 4):
		1:
			return Rect2i(
				Vector2i(-footprint_size.y, 0),
				Vector2i(footprint_size.y, footprint_size.x)
			)
		2:
			return Rect2i(-footprint_size, footprint_size)
		3:
			return Rect2i(
				Vector2i(0, -footprint_size.x),
				Vector2i(footprint_size.y, footprint_size.x)
			)
	return Rect2i(Vector2i.ZERO, footprint_size)


func _is_block_inside(
	target: Vehicle,
	block: Block,
	half_size: Vector2
) -> bool:
	for cell: Vector2i in block.get_occupied_cells():
		var cell_origin := Vector2(cell) * TILE_SIZE
		for corner: Vector2 in CELL_CORNERS:
			var point := to_local(target.to_global(
				cell_origin + corner * TILE_SIZE
			))
			if (
				point.x < -half_size.x - CONTAINMENT_EPSILON
				or point.y < -half_size.y - CONTAINMENT_EPSILON
				or point.x > half_size.x + CONTAINMENT_EPSILON
				or point.y > half_size.y + CONTAINMENT_EPSILON
			):
				return false
	return true


func _refresh_docked_vehicle() -> void:
	var previous := _docked_vehicle
	var current: Vehicle
	if (
		is_instance_valid(previous)
		and candidate_vehicles.has(previous)
		and is_vehicle_fully_inside(previous)
	):
		current = previous
	for index in range(candidate_vehicles.size() - 1, -1, -1):
		var target := candidate_vehicles[index]
		if not is_instance_valid(target):
			candidate_vehicles.remove_at(index)
			continue
		if (
			current == null
			and is_vehicle_fully_inside(target)
		):
			current = target
		elif (
			current != previous
			and is_vehicle_fully_inside(target)
			and target.get_instance_id() < current.get_instance_id()
		):
			current = target
	if current == previous:
		return
	_docked_vehicle = current
	docked_vehicle_changed.emit(_docked_vehicle)


func _on_docking_body_entered(body: Node2D) -> void:
	var entered_vehicle := body as Vehicle
	track_candidate_vehicle(entered_vehicle)


func _on_docking_body_exited(body: Node2D) -> void:
	var exited_vehicle := body as Vehicle
	untrack_candidate_vehicle(exited_vehicle)
