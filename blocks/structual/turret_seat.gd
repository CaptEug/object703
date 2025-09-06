class_name TurretSeat
extends Block

var load:float
var rotation_plain:RigidBody2D

func _ready():
	rotation_plain = find_child("RotationPlain") as RigidBody2D
