class_name Weapon
extends Block

@export var supply_port: Vector2i = Vector2i.ZERO
@export var shoot_range: float
@export var reload: float
@export var spread: float
@export var shells: Array
# SHOOTING
@export var muzzles: Array[Marker2D]
@export var muzzle_energy: float
@export var animplayer: AnimationPlayer
@export var gun_fire_sound: AudioStreamPlayer2D
# TURRET
@export var turret: Sprite2D
@export var rotation_speed: float # rads per second
@export var traverse: Array # degree

var current_muzzle:int = 0
@onready var reload_timer: Timer = create_reload_timer()
var loaded:bool = false
var loading:bool = false
var shell_loaded: PackedScene
var targeting:= Callable()


func _physics_process(delta):
	if vehicle:
		print(edge_sockets)
		if not loading and not loaded:
			if request_ammo():
				start_reload()


func request_ammo() -> bool:
	var ammo_recived : bool
	for shell in shells:
		var ammo_request := {shell: 1}
		ammo_recived = vehicle.supply_system.supply_items(self, ammo_request)
	return ammo_recived


func start_reload():
	loading = true
	reload_timer.start()


func create_reload_timer() -> Timer:
	var timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = reload
	timer.timeout.connect(_on_reload_timer_timeout)
	add_child(timer)
	return timer


func _on_reload_timer_timeout():
	loaded = true
	loading = false


func fire():
	if not loaded:
		return
	shoot(muzzles[current_muzzle], shell_loaded)
	if animplayer:
		animplayer.play('recoil'+str(current_muzzle))
	current_muzzle = current_muzzle+1 if current_muzzle+1 < muzzles.size() else 0
	if gun_fire_sound:
		gun_fire_sound.play()
	shell_loaded = null
	loaded = false


func shoot(muz:Marker2D, shell_picked:PackedScene):
	var shell = shell_picked.instantiate()
	shell.from = vehicle
	var gun_rotation = muz.global_rotation
	shell.global_position = muz.global_position
	#map.add_child(shell)
	
	if shell.max_thrust:
		shell.target_dir = Vector2.UP.rotated(gun_rotation).rotated(randf_range(-spread, spread))
	
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	var dir = Vector2.UP.rotated(gun_rotation).rotated(randf_range(-spread, spread))
	shell.apply_impulse(dir * muzzle_energy)
	
	# recoil force simulation
	
