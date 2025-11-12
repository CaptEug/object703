extends Line2D

@export var max_length:= 10

var min_spawn_distance:= 1.0
var trail_points:= []
var lifetime:float = 2.0
var tick_speed:= 0.05
var tick:= 0.0
var wild_speed:= 0.1
var point_age:= [0.0]

@onready var canvas_mod = get_tree().current_scene.find_child("CanvasModulate") as CanvasModulate

func _ready():
	clear_points()


func fade():
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, lifetime)


func _process(delta):
	add_trail_point(global_position)
	var real_points = []
	var start = trail_points[-1]
	
	if trail_points.size() > max_length:
		trail_points.pop_front()
	
	for i in trail_points.size():
		real_points.append(trail_points[i] - start)
	points = real_points
	
	#if start.distance_to(trail_points[0]) < min_spawn_distance:
		#queue_free()
	
	var c = canvas_mod.color
	# Compute per-channel inverse, avoid divide by zero
	var inv = Color(1.0 / max(c.r, 0.001), 1.0 / max(c.g, 0.001), 1.0 / max(c.b, 0.001))
	modulate = inv



func add_trail_point(point_pos:Vector2):
	if trail_points.size() > 0 and point_pos.distance_to(trail_points[-1]) < min_spawn_distance:
		return
	point_age.append(0.0)
	trail_points.append(point_pos)
