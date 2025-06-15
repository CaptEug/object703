class_name Weapon
extends Block

var reload:float
var rotation_speed:float  # rads per second
var traverse:Array # degree
var muzzle_energy:float
var turret:Sprite2D 
var muzzle:Marker2D
var animplayer:AnimationPlayer
var spread:float

var reload_timer:Timer
var loaded:bool = false

# Called when the node enters the scene tree for the first time.
func _ready():
	super._ready()
	reload_timer = Timer.new()
	reload_timer.wait_time = reload
	reload_timer.timeout.connect(_on_timer_timeout)
	add_child(reload_timer)
	reload_timer.start()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass

func aim(delta, target_pos):
	var target_angle = (target_pos - global_position).angle() - rotation + deg_to_rad(90)
	if traverse:
		var min_angle = deg_to_rad(traverse[0])
		var max_angle = deg_to_rad(traverse[1])
		target_angle = clamp(wrapf(target_angle, -PI, PI), min_angle, max_angle)
	var angle_diff = wrapf(target_angle - turret.rotation, -PI, PI)
	turret.rotation += clamp(angle_diff, -rotation_speed * delta, rotation_speed * delta)

func fire(shell_scene:PackedScene):
	if loaded:
		var shell = shell_scene.instantiate()
		var gun_rotation = muzzle.global_rotation
		get_tree().current_scene.add_child(shell)
		shell.global_position = muzzle.global_position
		shell.apply_impulse(Vector2.UP.rotated(gun_rotation).rotated(randf_range(-spread, spread)) * muzzle_energy)
		apply_impulse(Vector2.DOWN.rotated(gun_rotation) * muzzle_energy)
		if animplayer:
			animplayer.play('recoil')
		reload_timer.start()
		loaded = false

func _on_timer_timeout():
	loaded = true
