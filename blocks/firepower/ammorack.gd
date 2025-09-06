class_name Ammorack
extends Block

var ammo_storage :float
var ammo_storage_cap:float
var explosion_area:Area2D
var explosion_shape:CollisionShape2D
var exploded:bool = false
var explosion_particle = preload("res://assets/particles/explosion.tscn")

func _ready():
	super._ready()
	explosion_area = find_child("ExplosionArea") as Area2D
	if explosion_area:
		explosion_shape = explosion_area.find_child("CollisionShape2D") as CollisionShape2D

func _process(delta):
	#update explosion radius
	explosion_shape.shape.radius = ammo_storage/2
	

func deduct_ammo(amount:float) ->bool:
	if amount <= ammo_storage:
		ammo_storage -= amount
		return true
	return false

func destroy():
	# Disconnect all joints before destroying
	disconnect_all()
	queue_free()
	if parent_vehicle:
		parent_vehicle.remove_block(self)
	explode()

func explode():
	if exploded:
		return
	var explosion = explosion_particle.instantiate()
	explosion.position = global_position
	explosion.emitting = true
	get_tree().current_scene.add_child(explosion)
	exploded = true
	var max_explosive_damage = ammo_storage * 10
	var explosion_radius = ammo_storage/2

	for block in explosion_area.get_overlapping_bodies():
		if block.has_method("damage"):
			var dist = global_position.distance_to(block.global_position)
			var dir = (block.global_position - global_position).normalized()
			var ratio = clamp(1.0 - dist / explosion_radius, 0.0, 1.0)
			var dmg = max_explosive_damage * ratio
			var impulse_strength = 10000.0 * dmg
			block.apply_impulse(dir * impulse_strength)
			block.damage(dmg)
