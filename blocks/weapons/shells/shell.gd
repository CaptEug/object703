class_name Shell
extends RigidBody2D

var shell_name:String
var type:String
var weight:float
var lifetime:float
var kenetic_damage:int
var explosive_weight:int
var shell_body:Area2D
var trail:Line2D

var stopped := false

# Called when the node enters the scene tree for the first time.
func _ready():
	init()
	var timer = Timer.new()
	timer.wait_time = lifetime
	timer.autostart = true
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)
	shell_body.body_entered.connect(_on_shell_body_entered)

func init():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass


func stop():
	stopped = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0
	set_physics_process(false)
	shell_body.queue_free()
	trail.fade()
	#await get_tree().create_timer(trail.lifetime).timeout
	#queue_free()


func _on_timer_timeout():
	trail.fade()
	await get_tree().create_timer(trail.lifetime).timeout
	queue_free()


func _on_shell_body_entered(block:Block):
	var block_hp = block.current_hp
	var damage_to_deal = min(kenetic_damage, block_hp)
	var momentum:Vector2 = weight * linear_velocity
	block.apply_impulse(momentum)
	block.damage(kenetic_damage)
	kenetic_damage -= damage_to_deal
	if kenetic_damage <= 0:
		stop()
