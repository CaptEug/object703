class_name Block
extends RigidBody2D

var current_hp:int
# Called when the node enters the scene tree for the first time.
func _ready():
	init()
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	pass # Replace with function body.

func init():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func damage(amount:int):
	current_hp -= amount
	print(str(name) + 'damage received:' + str(amount))
	if current_hp <= 0:
		queue_free()
