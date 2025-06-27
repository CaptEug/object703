class_name Shell
extends RigidBody2D

var shell_name:String
var type:String
var weight:float
var lifetime:float
var kenetic_damage:int
var max_explosive_damage:int
var explosion_radius:int
var explosion_area:Area2D
var explosion_shape:CollisionShape2D
var shell_body:Area2D
var trail:Line2D

var stopped := false
var explosion_particle = preload("res://assets/particles/explosion.tscn")

# Called when the node enters the scene tree for the first time.
func _ready():
	init()
	var timer = Timer.new()
	timer.wait_time = lifetime
	timer.autostart = true
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)
	shell_body.body_entered.connect(_on_shell_body_entered)
	if max_explosive_damage:
		explosion_shape.shape.radius = explosion_radius

func init():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass

func explode():
	var explosion = explosion_particle.instantiate()
	explosion.emitting = true
	add_child(explosion)
	
	for block in explosion_area.get_overlapping_bodies():
		if block.has_method("damage"):
			var dist = global_position.distance_to(block.global_position)
			var dir = (block.global_position - global_position).normalized()
			var ratio = clamp(1.0 - dist / explosion_radius, 0.0, 1.0)
			var dmg = max_explosive_damage * ratio
			var impulse_strength = 100000.0 * ratio
			block.apply_impulse(dir * impulse_strength)
			block.damage(dmg)

func stop():
	shell_body.queue_free()
	stopped = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0
	set_physics_process(false)
	trail.fade()


func _on_timer_timeout():
	trail.fade()
	await get_tree().create_timer(trail.lifetime).timeout
	queue_free()


func _on_shell_body_entered(block:Block):
	var block_hp = block.current_hp
	if block_hp >= 0:
		var damage_to_deal = min(kenetic_damage, block_hp)
		print(kenetic_damage)
		print(block_hp)
		var momentum:Vector2 = weight * linear_velocity
		block.apply_impulse(momentum)
		block.damage(damage_to_deal)
		kenetic_damage -= damage_to_deal
		if kenetic_damage <= 0:
			if max_explosive_damage:
				explode()
			stop()
