class_name Weapon
extends Block

var range:float
var reload:float
var ammo_cost:float
var rotation_speed:float  # rads per second
var traverse:Array # degree
var muzzle_energy:float
var turret:Sprite2D 
var muzzles:Array
var current_muzzle:int = 0
var animplayer:AnimationPlayer
var spread:float

var reload_timer:Timer
var loaded:bool = false
var detection_area:Area2D
var icons:Dictionary = {"normal":"res://assets/icons/turret_icon.png","selected":"res://assets/icons/turret_icon_n.png"}

# Called when the node enters the scene tree for the first time.
func _ready():
	super._ready()
	generate_detection_area()
	reload_timer = Timer.new()
	reload_timer.wait_time = reload
	reload_timer.timeout.connect(_on_timer_timeout)
	add_child(reload_timer)
	reload_timer.start()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass

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
			points.append(Vector2(cos(angle), sin(angle)) * range)
		draw_line(Vector2.ZERO, points[0], line_color, line_width)
		draw_line(Vector2.ZERO, points[-1], line_color, line_width)
		draw_polyline(points, line_color, line_width)
	else:
		draw_arc(Vector2.ZERO, range, 0, TAU, segments, line_color, 2.0)

func generate_detection_area():
	# Get or create Area2D
	detection_area = Area2D.new()
	add_child(detection_area)
	if traverse:
		var segments: int = 32
		var start_angle = deg_to_rad(traverse[0]-90)
		var end_angle = deg_to_rad(traverse[-1]-90)
		var points: PackedVector2Array = [Vector2.ZERO]
		var collision_polygon = CollisionPolygon2D.new()
		
		for i in range(segments + 1):
			var t = i / float(segments)
			var angle = lerp(start_angle, end_angle, t)
			points.append(Vector2(cos(angle), sin(angle)) * range)

		collision_polygon.polygon = points
		detection_area.add_child(collision_polygon)
	else:
		var collision_shape = CollisionShape2D.new()
		var circle = CircleShape2D.new()
		circle.radius = range
		collision_shape.shape = circle
		detection_area.add_child(collision_shape)

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
		shoot(muzzles[current_muzzle], shell_scene)
		if animplayer:
			animplayer.play('recoil'+str(current_muzzle))
		reload_timer.start()
		current_muzzle = current_muzzle+1 if current_muzzle+1 < muzzles.size() else 0
		loaded = false

func shoot(muz:Marker2D, shell_scene:PackedScene):
	var shell = shell_scene.instantiate()
	shell.from = self
	var gun_rotation = muz.global_rotation
	get_tree().current_scene.add_child(shell)
	shell.global_position = muz.global_position
	shell.apply_impulse(Vector2.UP.rotated(gun_rotation).rotated(randf_range(-spread, spread)) * muzzle_energy)
	apply_impulse(Vector2.DOWN.rotated(gun_rotation) * muzzle_energy)

func _on_timer_timeout():
	loaded = true
