class_name Block
extends RigidBody2D

# Called when the node enters the scene tree for the first time.
func _ready():
	mass = get_weight()*100
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func get_weight() -> float:
	return 0.0
