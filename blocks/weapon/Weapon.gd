class_name Weapon
extends Block

enum MountType {
	FIXED_GUN,
	INTEGRATED_TURRET,
}

enum WeaponState {
	EMPTY,
	RELOADING,
	READY,
}

signal weapon_status_changed

@export_category("Weapon")
@export var mount_type: MountType = MountType.FIXED_GUN
@export var shoot_range: float = 0.0 # tiles; 0 keeps the projectile's own range
@export var reload: float = 1.0
@export var spread: float = 0.0 # radians
@export var shells: Array[String] = []
@export var muzzle_energy: float = 10000.0

@export_category("Firing")
@export var muzzles: Array[Marker2D] = []
@export var animplayer: AnimationPlayer
@export var gun_fire_sound: AudioStreamPlayer2D

@export_category("Integrated Turret")
@export var turret: Node2D
@export var rotation_speed: float = PI # radians per second
@export var traverse: Vector2 = Vector2(-180.0, 180.0) # left/right degrees

var state: WeaponState = WeaponState.EMPTY
var trigger_held := false
var aim_target_world := Vector2.ZERO
var has_aim_target := false
var selected_ammo_id := ""
var loaded_ammo_id := ""
var shell_loaded: PackedScene
var current_muzzle := 0

var reload_timer: Timer
var ammo_retry_time := 0.0
const AMMO_RETRY_INTERVAL := 0.25


func has_information_panel() -> bool:
	return true


func _ready() -> void:
	super()
	reload_timer = Timer.new()
	reload_timer.one_shot = true
	reload_timer.timeout.connect(_on_reload_timer_timeout)
	add_child(reload_timer)

func _physics_process(delta: float) -> void:
	if vehicle == null:
		return

	if vehicle.has_aim_command():
		set_aim_target(vehicle.get_aim_target())
	else:
		clear_aim_target()
	set_trigger_held(vehicle.get_fire_command())
	if mount_type == MountType.INTEGRATED_TURRET:
		_update_integrated_turret(delta)

	match state:
		WeaponState.EMPTY:
			ammo_retry_time -= delta
			if ammo_retry_time <= 0.0:
				_try_start_reload()
				ammo_retry_time = AMMO_RETRY_INTERVAL
		WeaponState.RELOADING:
			pass
		WeaponState.READY:
			if trigger_held:
				_fire_loaded_round()

func set_aim_target(world_position: Vector2) -> void:
	aim_target_world = world_position
	has_aim_target = true

func clear_aim_target() -> void:
	has_aim_target = false

func set_trigger_held(pressed: bool) -> void:
	trigger_held = pressed

func select_ammo(item_name: String) -> bool:
	if item_name.is_empty():
		selected_ammo_id = ""
		weapon_status_changed.emit()
		return true
	if not shells.has(item_name) or not _is_valid_ammo(item_name):
		return false
	selected_ammo_id = item_name
	weapon_status_changed.emit()
	return true

func get_state_name() -> String:
	match state:
		WeaponState.EMPTY:
			return "Empty"
		WeaponState.RELOADING:
			return "Reloading"
		WeaponState.READY:
			return "Ready"
	return "Unknown"

func get_reload_progress() -> float:
	if state == WeaponState.READY:
		return 1.0
	if state != WeaponState.RELOADING or reload_timer == null:
		return 0.0
	if reload_timer.wait_time <= 0.0:
		return 1.0
	return clampf(1.0 - reload_timer.time_left / reload_timer.wait_time, 0.0, 1.0)

func _update_integrated_turret(delta: float) -> void:
	if turret == null or not has_aim_target:
		return
	var direction := aim_target_world - turret.global_position
	if direction.is_zero_approx():
		return

	var desired_world_rotation := direction.angle() + PI * 0.5
	var desired_local_rotation := wrapf(desired_world_rotation - global_rotation, -PI, PI)
	var minimum := deg_to_rad(minf(traverse.x, traverse.y))
	var maximum := deg_to_rad(maxf(traverse.x, traverse.y))
	desired_local_rotation = clampf(desired_local_rotation, minimum, maximum)

	var next_rotation := rotate_toward(
		turret.rotation,
		desired_local_rotation,
		maxf(rotation_speed, 0.0) * delta
	)
	if maximum - minimum >= TAU - 0.001:
		turret.rotation = wrapf(next_rotation, -PI, PI)
	else:
		turret.rotation = clampf(next_rotation, minimum, maximum)

func _try_start_reload() -> bool:
	if state != WeaponState.EMPTY or vehicle == null:
		return false
	for item_name: String in _get_ammo_candidates():
		if not vehicle.supply_system.can_supply_item(self, item_name, 1):
			continue
		if not vehicle.supply_system.supply_item(self, item_name, 1):
			continue
		var shell_scene := ItemDB.get_item_by_name(item_name).get("shell_scene") as PackedScene
		if shell_scene == null:
			continue
		loaded_ammo_id = item_name
		shell_loaded = shell_scene
		_set_state(WeaponState.RELOADING)
		reload_timer.start(maxf(reload, 0.001))
		return true
	return false

func _get_ammo_candidates() -> Array[String]:
	var result: Array[String] = []
	if (
		not selected_ammo_id.is_empty()
		and shells.has(selected_ammo_id)
		and _is_valid_ammo(selected_ammo_id)
	):
		result.append(selected_ammo_id)
	for item_name: String in shells:
		if item_name != selected_ammo_id and _is_valid_ammo(item_name):
			result.append(item_name)
	return result

func _is_valid_ammo(item_name: String) -> bool:
	var item_data := ItemDB.get_item_by_name(item_name)
	return (
		not item_data.is_empty()
		and ItemDB.has_subclass(item_name, ItemDB.ItemSubclass.AMMO)
		and item_data.get("shell_scene") is PackedScene
	)

func _on_reload_timer_timeout() -> void:
	if state != WeaponState.RELOADING:
		return
	if shell_loaded == null:
		_clear_chamber()
		_set_state(WeaponState.EMPTY)
		return
	_set_state(WeaponState.READY)

func _fire_loaded_round() -> bool:
	if state != WeaponState.READY or shell_loaded == null or muzzles.is_empty():
		return false
	if current_muzzle < 0 or current_muzzle >= muzzles.size():
		current_muzzle = 0
	var muzzle := muzzles[current_muzzle]
	if not is_instance_valid(muzzle):
		return false
	if not _spawn_projectile(muzzle, shell_loaded):
		return false

	var animation_name := "recoil%d" % current_muzzle
	if animplayer != null and animplayer.has_animation(animation_name):
		animplayer.play(animation_name)
	if gun_fire_sound != null:
		gun_fire_sound.play()

	current_muzzle = (current_muzzle + 1) % muzzles.size()
	_clear_chamber()
	_set_state(WeaponState.EMPTY)
	ammo_retry_time = 0.0
	return true

func _spawn_projectile(muzzle: Marker2D, shell_scene: PackedScene) -> bool:
	var shell := shell_scene.instantiate() as Projectile
	if shell == null:
		return false

	var direction := Vector2.UP.rotated(muzzle.global_rotation)
	direction = direction.rotated(randf_range(-spread, spread)).normalized()
	shell.source_vehicle = vehicle
	shell.source_weapon = self
	shell.global_position = muzzle.global_position
	shell.spawn_position = muzzle.global_position
	shell.rotation = direction.angle() + PI * 0.5
	if shoot_range > 0.0:
		shell.max_range = maxi(1, roundi(shoot_range))
	get_tree().current_scene.add_child(shell)

	var shell_mass := maxf(shell.weight, 0.001)
	var velocity := sqrt(maxf(2.0 * muzzle_energy / shell_mass, 0.0))
	var impulse := direction * shell_mass * velocity
	shell.apply_impulse(impulse)

	var recoil_offset := muzzle.global_position - vehicle.global_position
	vehicle.apply_impulse(-impulse, recoil_offset)
	return true

func _clear_chamber() -> void:
	loaded_ammo_id = ""
	shell_loaded = null
	weapon_status_changed.emit()


func _set_state(new_state: WeaponState) -> void:
	if state == new_state:
		return
	state = new_state
	weapon_status_changed.emit()
