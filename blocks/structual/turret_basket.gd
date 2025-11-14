extends RigidBody2D

var joint:PinJoint2D

func _ready() -> void:
	joint = get_parent().find_child("PinJoint2D") as PinJoint2D
