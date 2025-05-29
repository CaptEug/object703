class_name Block
extends RigidBody2D

var current_hp:int
# Called when the node enters the scene tree for the first time.
func _ready():
	init()
	pass # Replace with function body.

func init():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func damage(amount:int):
	print(str(name)+'receive damage:'+str(amount))
	current_hp -= amount
	if current_hp <= 0:
		queue_free()
