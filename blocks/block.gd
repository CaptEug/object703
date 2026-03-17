class_name Block
extends Node2D

const TILE_SIZE := Globals.TILE_SIZE

var vehicle : Vehicle
var origin_cell : Vector2i
@export var size : Vector2i = Vector2i(1,1)
var rotation_index : int = 0          # 0:0 1:90 2:180 3:270 degree
@onready var collision : CollisionShape2D = $CollisionShape2D

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


# Block Status

func damage(amount:int, type:String):
	var dmg_taken = amount
	match type:
		"KINETIC": dmg_taken *= k_a
		"EXPLOSIVE": dmg_taken *= e_a
	 
	hp -= dmg_taken
	if hp <= 0:
		vehicle.destroy_block(self)
