class_name Tiles
extends StaticBody2D

var layer:TileMapLayer
var cell:Vector2i
var terrain_set:int
var max_hp:int
var current_hp:int
var kinetic_absorb:float
var explosice_absorb:float

var shard_particle_path = "res://assets/particles/shard.tscn"
@export var shard_gradient:Gradient

func _ready():
	pass # Replace with function body.


func _process(delta):
	pass


func damage(amount:int):
	current_hp -= amount
	# phase 1
	if current_hp <= max_hp * 0.5:
		pass
	
	# phase 2
	if current_hp <= max_hp * 0.25:
		pass
	
	# phase 3
	if current_hp <= 0:
		destroy()


func destroy():
	layer.erase_cell(cell)
	layer.set_cells_terrain_connect([cell], terrain_set, -1)
	
	queue_free()
	var shard_particle = load(shard_particle_path).instantiate()
	shard_particle.position = global_position
	get_tree().current_scene.add_child(shard_particle)
