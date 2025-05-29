class_name Block
extends RigidBody2D

var current_hp:int
var weight: float
var block_name: String
var size: Vector2
var parent_vehicle: Vehicle = null  


func _ready():
	init()
	mass = weight
	parent_vehicle = get_parent() as Vehicle
	if parent_vehicle:
		parent_vehicle._add_block(self)
	pass # Replace with function body.

func init():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func damage(amount:int):
	current_hp -= amount
	if current_hp <= 0:
		if parent_vehicle:
			parent_vehicle.remove_block(self)
		queue_free()
