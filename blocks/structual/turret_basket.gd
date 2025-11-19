extends RigidBody2D

var joint:PinJoint2D

func _process(delta: float) -> void:
	print(1.0/PhysicsServer2D.body_get_direct_state(get_rid()).inverse_inertia)
