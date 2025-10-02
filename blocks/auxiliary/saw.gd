extends RigidBody2D

var spark_particle = preload("res://assets/particles/spark.tscn")

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if get_parent().on:
		var count = state.get_contact_count()
		for i in range(count):
			var contact_local = state.get_contact_local_position(i)
			var contact_normal = state.get_contact_local_normal(i)
			var collider = state.get_contact_collider_object(i)
			var spark = spark_particle.instantiate()
			spark.position = contact_local
			spark.rotation = contact_normal.angle() - PI/2
			spark.emitting = true
			get_tree().current_scene.add_child(spark)
