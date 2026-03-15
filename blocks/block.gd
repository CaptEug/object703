class_name Block
extends Node2D

var vehicle : Vehicle
var origin_cell : Vector2i
@export var size : Vector2i = Vector2i(1,1)
var block_rotation := 0
@export var collision : CollisionShape2D

# game property
@export var block_name : String
@export var max_hp : int
var hp : int
@export var k_a : float = 1.0
@export var e_a : float = 1.0
@export var mass : int


func initialize(v, cell:Vector2i):
	vehicle = v
	origin_cell = cell
	position = cell * vehicle.TILE_SIZE


func get_occupied_cells() -> Array:
	var cells := []
	for x in size.x:
		for y in size.y:
			cells.append(origin_cell + Vector2i(x,y))
	
	return cells


func damage(amount:int, type:String):
	var dmg_taken = amount
	match type:
		"KINETIC": dmg_taken *= k_a
		"EXPLOSIVE": dmg_taken *= e_a
	 
	hp -= dmg_taken
	if hp <= 0:
		vehicle.destroy_block(self)
