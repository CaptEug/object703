class_name Block
extends Node2D

const TILE_SIZE := Globals.TILE_SIZE

var vehicle : Vehicle
var origin_cell : Vector2i
var local_cells : Array[Vector2i]
@export var size : Vector2i = Vector2i(1,1)
var rotation_index : int = 0          # 0:0 1:90 2:180 3:270 degree
@onready var collision : CollisionShape2D = $CollisionShape2D
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
@export var edge_sockets: Dictionary = {}    # { local_cell: { side:int -> bool } }

# game property
@export var block_name : String
@export var max_hp : int
var hp : int
@export var k_a : float = 1.0
@export var e_a : float = 1.0
@export var mass : int = 1


# Block Placement

func update_transform(v, cell:Vector2i, rotation_i:int):
	vehicle = v
	origin_cell = cell
	rotation_index = rotation_i
	position = (Vector2(origin_cell) * TILE_SIZE) + (Vector2(get_rotated_size()) * TILE_SIZE) / 2
	rotation = rotation_index * PI * 0.5
	if edge_sockets.is_empty():
		build_default_edge_sockets()


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
	build_local_cells()
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


func get_transformd_cell(cell:Vector2i):
	var raw_cells : Array[Vector2i] = []
	for c in local_cells:
		raw_cells.append(rotate_cell_raw(c, rotation_index))
	
	var min_x := raw_cells[0].x
	var min_y := raw_cells[0].y
	for c in raw_cells:
		min_x = min(min_x, c.x)
		min_y = min(min_y, c.y)
	
	var rotated_cell = rotate_cell_raw(cell, rotation_index) - Vector2i(min_x, min_y)
	
	return origin_cell + rotated_cell


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

func damage(amount:int, type:String):
	var dmg_taken = amount
	match type:
		"KINETIC": dmg_taken *= k_a
		"EXPLOSIVE": dmg_taken *= e_a
	 
	hp -= dmg_taken
	if hp <= 0:
		vehicle.destroy_block(self)
