class_name Shell
extends RigidBody2D

var shell_name:String
var type:String
var weight:float
var lifetime:float
var kenetic_damage:int
var max_explosive_damage:int
var explosion_radius:int
var explosion_area:Area2D = null
var explosion_shape:CollisionShape2D
var max_thrust:float
var thrust:float = 0.0
var acceleration:float
var target_dir:Vector2
var shell_body:Area2D
var shell_trail:Line2D
var smoke_trail:Line2D

var from:Vehicle
var stopped := false
var explosion_particle = preload("res://assets/particles/explosion.tscn")
var spark_particle = preload("res://assets/particles/spark.tscn")


func _ready():
	shell_body = find_child("Area2D") as Area2D
	shell_trail = find_child("ShellTrail") as Line2D
	smoke_trail = find_child("SmokeTrail") as Line2D
	explosion_area = find_child("ExplosionArea") as Area2D
	if explosion_area:
		explosion_shape = explosion_area.find_child("CollisionShape2D") as CollisionShape2D
	if max_explosive_damage:
		explosion_shape.shape.radius = explosion_radius
	collision_layer = 0
	collision_mask = 0
	linear_damp = 0.1
	mass = weight/1000
	var timer = Timer.new()
	timer.wait_time = lifetime
	timer.autostart = true
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)
	shell_body.collision_mask = 3
	shell_body.body_entered.connect(_on_shell_body_entered)


func _physics_process(delta):
	if max_thrust and not stopped:
		propel(delta)

func propel(delta):
	thrust = clamp(thrust + delta * acceleration, 0, max_thrust)
	self.apply_force(thrust * target_dir)

func explode():
	var explosion = explosion_particle.instantiate()
	explosion.position = global_position
	explosion.emitting = true
	get_tree().current_scene.add_child(explosion)
	
	await get_tree().physics_frame
	
	for body in explosion_area.get_overlapping_bodies():
		if body.has_method("damage"):
			var dist = global_position.distance_to(body.global_position)
			var dir = (body.global_position - global_position).normalized()
			var ratio = clamp(1.0 - dist / explosion_radius, 0.0, 1.0)
			var dmg = max_explosive_damage * ratio
			var impulse_strength = dmg
			if body is Block:
				body.apply_impulse(dir * impulse_strength)
			body.damage(dmg)

func stop():
	stopped = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0
	set_physics_process(false)
	shell_body.queue_free()
	shell_trail.visible = false
	smoke_trail.fade()


func _on_timer_timeout():
	shell_trail.fade()
	smoke_trail.fade()
	await get_tree().create_timer(smoke_trail.lifetime).timeout
	queue_free()


func _on_shell_body_entered(body):
	if body is Block:
		var vehicle_hit = body.parent_vehicle
		#check if the vehicle is not self
		if vehicle_hit == from and from != null:
			return
	
		# apply hit inpluse
		var momentum:Vector2 = mass * linear_velocity
		body.apply_impulse(momentum)
	
	var body_hp = body.current_hp
	if body_hp >= 0:
		var damage_to_deal = min(kenetic_damage, body_hp)
		body.damage(damage_to_deal)
		kenetic_damage -= damage_to_deal
		if kenetic_damage <= 0:
			if max_explosive_damage:
				explode()
			else:
				var spark = spark_particle.instantiate()
				spark.position = global_position
				spark.rotation = linear_velocity.angle()
				spark.emitting = true
				get_tree().current_scene.add_child(spark)
			stop()
