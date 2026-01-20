class_name Ammorack
extends Cargo

const ACCEPT:= ["ammo"]
var ammo_storage :float
var explosion_area:Area2D
var explosion_shape:CollisionShape2D
var exploded:bool = false
var explosion_particle = preload("res://assets/particles/explosion.tscn")

func _ready():
	super._ready()
	explosion_area = find_child("ExplosionArea") as Area2D
	if explosion_area:
		explosion_shape = explosion_area.find_child("CollisionShape2D") as CollisionShape2D

func _process(_delta):
	super._process(_delta)
	#update explosion radius
	explosion_shape.shape.radius = ammo_storage/2


func destroy():
	explode()
	super.destroy()


func explode():
	if exploded:
		return
	var explosion = explosion_particle.instantiate()
	explosion.position = global_position
	explosion.emitting = true
	get_tree().current_scene.add_child(explosion)
	exploded = true
	var max_explosive_damage = ammo_storage * 5
	var explosion_radius = ammo_storage/2
	ammo_storage = 0
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
