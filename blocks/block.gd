class_name Block
extends Node2D

signal health_changed
signal block_destroyed

const TILE_SIZE := Globals.TILE_SIZE

var vehicle : Vehicle
var block_host: Node
var assembly: BlockAssembly
var origin_cell : Vector2i
var local_cells : Array[Vector2i]
@export var size : Vector2i = Vector2i(1,1)
var rotation_index : int = 0   # 0:0 1:90 2:180 3:270 degree
@onready var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
enum Side {
	UP,
	RIGHT,
	DOWN,
	LEFT
}
const SIDE_DIRS := {
	Side.UP: Vector2i.UP,
	Side.RIGHT: Vector2i.RIGHT,
	Side.DOWN: Vector2i.DOWN,
	Side.LEFT: Vector2i.LEFT,
}
const OPPOSITE_SIDE := {
	Side.UP: Side.DOWN,
	Side.RIGHT: Side.LEFT,
	Side.DOWN: Side.UP,
	Side.LEFT: Side.RIGHT,
}
@export var edge_sockets: Dictionary[Vector2i,Dictionary] = {}    # { local_cell: { side:int -> bool } }

# game property
var block_id: int = BlockDB.INVALID_BLOCK_ID
var block_name := ""
var max_hp := 0.0
var _local_hp := 0.0
var _hp_managed_by_host := false
var hp: float:
	get:
		if (
			_hp_managed_by_host
			and block_host != null
			and block_host.has_method("get_block_hp_at")
		):
			return float(block_host.call("get_block_hp_at", origin_cell))
		return _local_hp
	set(value):
		_local_hp = maxf(value, 0.0)
var mass := 0.0


func _ready():
	if block_id == BlockDB.INVALID_BLOCK_ID:
		block_id = BlockDB.get_id_for_name(block_name)
	if block_id == BlockDB.INVALID_BLOCK_ID:
		block_id = BlockDB.get_id_for_scene(scene_file_path)
	if BlockDB.has_block(block_id):
		var definition := BlockDB.get_block(block_id)
		block_name = BlockDB.get_block_name(block_id)
		var base_size: Vector2i = definition.get("size", size)
		var base_units := maxi(base_size.x * base_size.y, 1)
		var configured_units := maxi(size.x * size.y, 1)
		var unit_scale := maxf(
			float(configured_units) / float(base_units),
			1.0
		)
		max_hp = BlockDB.get_max_hp(block_id) * unit_scale
		mass = roundi(
			float(definition.get("mass", mass)) * unit_scale
		)
	_local_hp = max_hp
	build_local_cells()
	if edge_sockets.is_empty():
		build_default_edge_sockets()
	refresh_shared_visual()


func has_information_panel() -> bool:
	return false


func get_information_panel_key() -> StringName:
	return &""


func is_power_consumer() -> bool:
	return false


func get_power_demand() -> float:
	return 0.0


func set_supplied_power(_amount: float) -> void:
	pass


func get_save_state() -> Dictionary:
	return {}


func apply_save_state(_state: Dictionary) -> void:
	pass


# Block Placement

func update_transform(v: Vehicle, cell:Vector2i, rotation_i:int):
	vehicle = v
	block_host = v
	assembly = v.block_assembly if v != null else null
	_hp_managed_by_host = false
	origin_cell = cell
	rotation_index = BlockDB.normalize_rotation(block_id, rotation_i)
	position = (Vector2(origin_cell) * TILE_SIZE) + (Vector2(get_rotated_size()) * TILE_SIZE) / 2
	rotation = rotation_index * PI * 0.5


func update_world_transform(
	world_host: Node,
	cell: Vector2i,
	rotation_i: int
) -> void:
	vehicle = null
	block_host = world_host
	assembly = null
	_hp_managed_by_host = true
	origin_cell = cell
	rotation_index = BlockDB.normalize_rotation(block_id, rotation_i)
	position = (
		Vector2(origin_cell) * TILE_SIZE
		+ Vector2(get_rotated_size()) * TILE_SIZE * 0.5
	)
	rotation = rotation_index * PI * 0.5


func get_assembly() -> BlockAssembly:
	if (
		block_host != null
		and block_host.has_method("get_assembly_at")
	):
		return block_host.call(
			"get_assembly_at",
			origin_cell
		) as BlockAssembly
	return assembly


func refresh_shared_visual() -> void:
	if not BlockDB.has_block(block_id):
		return
	var variant := BlockVisualSystem.resolve_variant(
		block_host,
		origin_cell,
		block_id,
		rotation_index
	)
	if variant.is_empty():
		return
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	BlockVisualSystem.apply_variant_to_sprite(sprite, variant)


func get_rotated_size() -> Vector2i:
	if rotation_index % 2 == 0:
		return size
	return Vector2i(size.y, size.x)


func get_occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var rs := get_rotated_size()
	for x in range(rs.x):
		for y in range(rs.y):
			cells.append(origin_cell + Vector2i(x, y))
	return cells


func build_local_cells() -> void:
	local_cells.clear()
	for x in range(size.x):
		for y in range(size.y):
			local_cells.append(Vector2i(x, y))


func build_default_edge_sockets() -> void:
	edge_sockets.clear()
	var occupied := {}
	for c in local_cells:
		occupied[c] = true
	
	for c in local_cells:
		var sides := {}
		for side in Side.values():
			var n : Vector2i = c + SIDE_DIRS[side]
			if not occupied.has(n):
				sides[side] = true
		if not sides.is_empty():
			edge_sockets[c] = sides


func rotate_cell_raw(cell: Vector2i, rot: int) -> Vector2i:
	match rot % 4:
		0: return cell
		1: return Vector2i(-cell.y, cell.x)
		2: return Vector2i(-cell.x, -cell.y)
		3: return Vector2i(cell.y, -cell.x)
	return cell


func rotate_side(side: int, rot: int) -> int:
	return wrapi(side + rot, 0, 4)


func get_transformed_edges() -> Dictionary:
	var result: Dictionary = {}
	var raw_cells: Array[Vector2i] = []
	
	for local_cell in edge_sockets.keys():
		raw_cells.append(rotate_cell_raw(local_cell, rotation_index))
	
	if raw_cells.is_empty():
		return result
	
	var min_x := raw_cells[0].x
	var min_y := raw_cells[0].y
	for c in raw_cells:
		min_x = min(min_x, c.x)
		min_y = min(min_y, c.y)
	
	for local_cell in edge_sockets.keys():
		var local_side_dict: Dictionary = edge_sockets[local_cell]
		var raw_cell := rotate_cell_raw(local_cell, rotation_index)
		var rotated_cell := raw_cell - Vector2i(min_x, min_y)
		var world_cell := origin_cell + rotated_cell
		if not result.has(world_cell):
			result[world_cell] = {}
		var world_side_dict: Dictionary = result[world_cell]
		for local_side in local_side_dict.keys():
			var world_side: int = rotate_side(local_side, rotation_index)
			world_side_dict[world_side] = local_side_dict[local_side]
	
	return result


func is_edge_connectable(cell: Vector2i, side: int) -> bool:
	var edges := get_transformed_edges()
	if not edges.has(cell):
		return false
	var side_dict: Dictionary = edges[cell]
	return side_dict.get(side, false)


# Block Status

func damage(
	amount: float,
	damage_type: StringName
) -> Dictionary:
	if (
		block_host == null
		or not block_host.has_method("damage_block_at")
	):
		return BlockDamage.miss()
	return block_host.call(
		"damage_block_at",
		origin_cell,
		amount,
		damage_type
	)


func apply_vehicle_damage_result(result: Dictionary) -> void:
	_local_hp = float(result.get("hp_after", _local_hp))
	health_changed.emit()
	if bool(result.get("destroyed", false)):
		block_destroyed.emit()


func notify_world_health_changed(destroyed: bool) -> void:
	health_changed.emit()
	if destroyed:
		block_destroyed.emit()
