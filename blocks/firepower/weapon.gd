class_name Weapon
extends Block

var detect_range:float
var reload:float
var ammo_cost:float
var rotation_speed:float # rads per second
var traverse:Array # degree
var muzzle_energy:float
var turret:Sprite2D 
var muzzles:Array
var current_muzzle:int = 0
var animplayer:AnimationPlayer
var spread:float
var shell_scene:PackedScene

var reload_timer:Timer
var loaded:bool = false
var loading:bool = false
var detect_area:Area2D
var connected_ammoracks := []
var targeting:= Callable()


func _ready():
	super._ready()
	turret = find_child("Turret") as Sprite2D
	for muz in turret.get_children():
		if muz is Marker2D:
			muzzles.append(muz)
	animplayer = find_child("AnimationPlayer") as AnimationPlayer
	reload_timer = Timer.new()
	reload_timer.one_shot = true
	reload_timer.wait_time = reload
	reload_timer.timeout.connect(_on_timer_timeout)
	add_child(reload_timer)



func _process(delta):
	super._process(delta)
	
	#check reload every frame
	if has_ammo():
		if not loading and not loaded:
			start_reload()
	
	#check targeting method
	if get_parent_vehicle():
		var control_method = get_parent_vehicle().control.get_method()
		if control_method == "manual_control":
			targeting = Callable(self, "manual_target")
		elif (control_method == "remote_control") or (control_method == "AI_control"):
			targeting = Callable(self, "auto_target")
		else:
			targeting = Callable()
	
	if targeting:
		targeting.call(delta)

func _draw():
	var line_color = Color(1,1,1)
	var line_width:float = 2.0
	var segments := 64
	if traverse:
		var start_angle = deg_to_rad(traverse[0]-90)
		var end_angle = deg_to_rad(traverse[1]-90)
		var points = []
		# Arc points
		points.append(Vector2.ZERO) # center
		for i in range(segments + 1):
			var t = i / float(segments)
			var angle = lerp(start_angle, end_angle, t)
			points.append(Vector2(cos(angle), sin(angle)) * detect_range)
		draw_line(Vector2.ZERO, points[0], line_color, line_width)
		draw_line(Vector2.ZERO, points[-1], line_color, line_width)
		draw_polyline(points, line_color, line_width)
	else:
		draw_arc(Vector2.ZERO, detect_range, 0, TAU, segments, line_color, 2.0)



func aim(delta, target_pos):
	var target_angle = (target_pos - global_position).angle() - rotation + deg_to_rad(90)
	if traverse:
		var min_angle = deg_to_rad(traverse[0])
		var max_angle = deg_to_rad(traverse[1])
		target_angle = clamp(wrapf(target_angle, -PI, PI), min_angle, max_angle)
	var angle_diff = wrapf(target_angle - turret.rotation, -PI, PI)
	turret.rotation += clamp(angle_diff, -rotation_speed * delta, rotation_speed * delta)
	# return true if aimed
	return abs(angle_diff) < deg_to_rad(1)


func fire():
	if not loaded:
		return
	shoot(muzzles[current_muzzle], shell_scene)
	if animplayer:
		animplayer.play('recoil'+str(current_muzzle))
	current_muzzle = current_muzzle+1 if current_muzzle+1 < muzzles.size() else 0
	loaded = false

func shoot(muz:Marker2D, shell_picked:PackedScene):
	var shell = shell_picked.instantiate()
	shell.from = parent_vehicle
	var gun_rotation = muz.global_rotation
	get_tree().current_scene.add_child(shell)
	shell.global_position = muz.global_position
	if shell.max_thrust:
		shell.target_dir = Vector2.UP.rotated(gun_rotation)
	shell.apply_impulse(Vector2.UP.rotated(gun_rotation).rotated(randf_range(-spread, spread)) * muzzle_energy)
	apply_impulse(Vector2.DOWN.rotated(gun_rotation) * muzzle_energy)

func start_reload():
	loading = true
	cost_ammo(ammo_cost)
	reload_timer.start()

func has_ammo() -> bool:
	connected_ammoracks.clear()
	find_all_connected_ammorack()
	var total_ammo = 0
	for ammorack in connected_ammoracks:
		total_ammo += ammorack.ammo_storage
	if total_ammo > ammo_cost:
		return true
	return false

func cost_ammo(amount:float):
	var remaining = amount
	for ammorack in connected_ammoracks:
		if ammorack.ammo_storage >= remaining:
			ammorack.ammo_storage -= remaining
			return
		else:
			remaining -= ammorack.ammo_storage
			ammorack.ammo_storage = 0

func _on_timer_timeout():
	loaded = true
	loading = false

func find_all_connected_ammorack():
	connected_ammoracks.clear()
	for block in get_all_connected_blocks():
		if block is Ammorack:
			connected_ammoracks.append(block)
	return connected_ammoracks



func auto_target(delta):
	var targets = get_parent_vehicle().targets
	var closest_target:Block
	
	if targets.size() > 0:
		closest_target = targets[0]
		for target in targets:
			var distance = global_position.distance_to(target.global_position)
			if distance < global_position.distance_to(closest_target.global_position):
				closest_target = target
	#fire if aimed
		if aim(delta, closest_target.global_position):
			fire()



func manual_target(delta):
	aim(delta, get_global_mouse_position())
	if Input.is_action_pressed("FIRE_MAIN"):
	# Skip firing if mouse is over UI
		if get_viewport().gui_get_hovered_control():
			return
		fire()
