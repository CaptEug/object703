class_name Weapon
extends Block

var range:float
var reload:float
var ammo_cost:float
var rotation_speed:float # rads per second
var traverse:Array # degree
var has_turret:bool
var muzzle_energy:float
var turret:Sprite2D 
var muzzles:Array
var current_muzzle:int = 0
var animplayer:AnimationPlayer
var gun_fire_sound:AudioStreamPlayer2D
var spread:float
var shells:Array
var broken_turret:Sprite2D

var reload_timer:Timer
var loaded:bool = false
var loading:bool = false
var shell_chosen:PackedScene
var connected_ammoracks := []
var targeting:= Callable()


func _ready():
	super._ready()
	turret = find_child("Turret") as Sprite2D
	has_turret = turret != null
	if has_turret:
		for muz in turret.get_children():
			if muz is Marker2D:
				muzzles.append(muz)
		broken_turret =  find_child("BrokenTurret") as Sprite2D
	else:
		muzzles.append(find_child("Muzzle") as Marker2D)
	
	animplayer = find_child("AnimationPlayer") as AnimationPlayer
	gun_fire_sound = find_child("GunFireSound") as AudioStreamPlayer2D
	reload_timer = Timer.new()
	reload_timer.one_shot = true
	reload_timer.wait_time = reload
	reload_timer.timeout.connect(_on_timer_timeout)
	add_child(reload_timer)



func _process(delta):
	super._process(delta)
	#check reload
	if not loading and not loaded:
		if find_ammo():
			start_reload()
	
	#check targeting method
	if parent_vehicle:
		var control_method = parent_vehicle.control.get_method()
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
	if turret:
		draw_set_transform(turret.position)
	if traverse:
		var start_angle = deg_to_rad(traverse[0]-90)
		var end_angle = deg_to_rad(traverse[1]-90)
		var points = []
		# Arc points
		points.append(Vector2.ZERO) # center
		for i in range(segments + 1):
			var t = i / float(segments)
			var angle = lerp(start_angle, end_angle, t)
			points.append(Vector2(cos(angle), sin(angle)) * range)
		draw_line(Vector2.ZERO, points[0], line_color, line_width)
		draw_line(Vector2.ZERO, points[-1], line_color, line_width)
		draw_polyline(points, line_color, line_width)
	else:
		draw_arc(Vector2.ZERO, range, 0, TAU, segments, line_color, 2.0)



func aim(delta, target_pos):
	var target_angle = (target_pos - global_position).angle() - global_rotation + deg_to_rad(90)
	var angle_diff = wrapf(target_angle, -PI, PI)
	if traverse:
		var min_angle = deg_to_rad(traverse[0])
		var max_angle = deg_to_rad(traverse[1])
		turret.rotation = clamp(turret.rotation, min_angle, max_angle)
	if has_turret:
		target_angle = (target_pos - turret.global_position).angle() - global_rotation + deg_to_rad(90)
		angle_diff = wrapf(target_angle - turret.rotation, -PI, PI)
		turret.rotation += clamp(angle_diff, -rotation_speed * delta, rotation_speed * delta)
		return abs(angle_diff) < deg_to_rad(1)
	# return true if aimeda
	return abs(angle_diff) < deg_to_rad(2)


func fire():
	if not loaded:
		return
	shoot(muzzles[current_muzzle], shell_chosen)
	if animplayer:
		animplayer.play('recoil'+str(current_muzzle))
	current_muzzle = current_muzzle+1 if current_muzzle+1 < muzzles.size() else 0
	if gun_fire_sound:
		gun_fire_sound.play()
	shell_chosen = null
	loaded = false

func shoot(muz:Marker2D, shell_picked:PackedScene):
	var shell = shell_picked.instantiate()
	shell.from = parent_vehicle
	var gun_rotation = muz.global_rotation
	get_tree().current_scene.add_child(shell)
	shell.global_position = muz.global_position
	if shell.max_thrust:
		shell.target_dir = Vector2.UP.rotated(gun_rotation).rotated(randf_range(-spread, spread))
	
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	var dir = Vector2.UP.rotated(gun_rotation).rotated(randf_range(-spread, spread))
	shell.apply_impulse(dir * muzzle_energy)
	#To simulate recoil force
	apply_impulse(Vector2.DOWN.rotated(gun_rotation) * muzzle_energy * 10)
	if on_turret:
		var block_grid = on_turret.get_turret_block_grid(self)
		var pos = (on_turret.calculate_block_center(block_grid) - Vector2(on_turret.size) * 8).rotated(on_turret.turret_basket.global_rotation)
		var t_dir = Vector2.DOWN.rotated(gun_rotation)
		on_turret.turret_basket.apply_impulse(t_dir * muzzle_energy * 1000, pos)

func start_reload():
	loading = true
	reload_timer.start()

func find_ammo() -> bool:
	connected_ammoracks.clear()
	find_all_connected_ammorack()
	if connected_ammoracks.is_empty():
		return false
	for ammorack in connected_ammoracks:
		var inv = ammorack.inventory
		for item in inv:
			if item == {}:
				continue
			if item["id"] in shells:
				shell_chosen = ItemDB.get_item(item["id"])["shell_scene"]
				return ammorack.take_item(item["id"], 1)
	return false


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
	var targets_in_range:= []
	
	for target in targets:
		if not is_instance_valid(target):
			continue  # skip freed objects
		if not target.is_inside_tree():
			continue  # skip nodes not in scene anymore
		if self.global_position.distance_to(target.global_position) <= range:
			if traverse:
				var min_angle = deg_to_rad(traverse[0])
				var max_angle = deg_to_rad(traverse[1])
				var target_angle = (target.global_position - global_position).angle() - global_rotation + deg_to_rad(90)
				if target_angle > min_angle and target_angle < max_angle:
					targets_in_range.append(target)
			else:
				targets_in_range.append(target)
	
	if targets_in_range.size() > 0:
		closest_target = targets_in_range[0]
		for target in targets_in_range:
			var distance = global_position.distance_to(target.global_position)
			if distance < global_position.distance_to(closest_target.global_position):
				closest_target = target
	#fire if aimed
		if aim(delta, closest_target.global_position):
			fire()



func manual_target(delta):
	print(1)
	aim(delta, get_global_mouse_position())
	if Input.is_action_pressed("FIRE_MAIN"):
	# Skip firing if mouse is over UI
		if get_viewport().gui_get_hovered_control():
			return
		fire()


func broke():
	super.broke()
	if turret:
		turret.visible = false
	if broken_turret:
		broken_turret.rotation = turret.rotation
		broken_turret.visible = true
