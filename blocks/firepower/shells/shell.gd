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
var last_pos:Vector2

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
	last_pos = global_position


func _physics_process(delta):
	check_shell_enter_tile(delta)
	if max_thrust and not stopped:
		propel(delta)

func propel(delta):
	thrust = clamp(thrust + delta * acceleration, 0, max_thrust)
	self.apply_force(thrust * target_dir)

func explode():
	var explosion_center = global_position
	var explosion = explosion_particle.instantiate()
	explosion.position = explosion_center
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
			body.damage(dmg, "explosive")
		
		if body is WallLayer:
			#explosion caluclation for tiles
			var tilemap = body
			var center_cell = tilemap.local_to_map(explosion_center)
			var tile_size:int = 16
			var r_tiles = int(explosion_radius / tile_size) + 1
			for y in range(center_cell.y - r_tiles, center_cell.y + r_tiles + 1):
				for x in range(center_cell.x - r_tiles, center_cell.x + r_tiles + 1):
					var cell = Vector2i(x, y)
					if not tilemap.get_celldata(cell):
						continue
					var cell_center_world = tilemap.map_to_local(cell) + Vector2(tile_size, tile_size) * 0.5
					# check circular distance
					var dist = explosion_center.distance_to(cell_center_world)
					if dist <= explosion_radius:
						var ratio = clamp(1.0 - dist / explosion_radius, 0.0, 1.0)
						var dmg = max_explosive_damage * ratio
						# this tile is inside explosion area
						tilemap.damage_tile(cell, dmg, "explosive")

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
	var body_hp:int
	var damage_to_deal:int
	if body is Block:
		var vehicle_hit = body.parent_vehicle
		#check if the vehicle is not self
		if vehicle_hit == from and from != null:
			return
		# apply hit inpluse
		var momentum:Vector2 = mass * linear_velocity
		body.apply_impulse(momentum)
		body_hp = body.current_hp
		if body_hp > 0:
			damage_to_deal = min(kenetic_damage, body_hp)
			body.damage(damage_to_deal, "kinetic")
			kenetic_damage -= damage_to_deal
		if kenetic_damage <= 0:
			if max_explosive_damage:
				explode()
			else:
				var spark = spark_particle.instantiate()
				spark.position = global_position
				spark.rotation = linear_velocity.angle()
				spark.emitting = true
				get_parent().add_child(spark)
			stop()

func check_shell_enter_tile(delta):
	var current_pos = global_position
	var space_state = get_world_2d().direct_space_state
	var query:= PhysicsRayQueryParameters2D.new()
	query.from = last_pos
	query.to = current_pos
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	
	if result and result.collider is WallLayer:
		var maplayer = result.collider
		var hit_pos: Vector2 = result.position
		var cell_contact: Vector2i = maplayer.local_to_map(hit_pos)
		var contact_celldata = maplayer.get_celldata(cell_contact)
		if contact_celldata:
			if contact_celldata["current_hp"] > 0:
				var damage_to_deal = min(kenetic_damage, contact_celldata["current_hp"])
				maplayer.damage_tile(cell_contact, damage_to_deal, "kinetic")
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
	last_pos = current_pos
