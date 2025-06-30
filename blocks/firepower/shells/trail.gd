extends Line2D

@export var wildness:= 10
#@export var min_spawn_distance := 5

var trail_points:= []
var lifetime:float
var tick_speed:= 0.05
var tick:= 0.0
var wild_speed:= 0.1
var point_age:= [0.0]

func _ready():
	clear_points()


func fade():
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, lifetime)


func _process(delta):
	add_trail_point(global_position)
	var real_points = []
	var start = trail_points[-1]
	if tick > tick_speed:
		tick = 0
		for i in trail_points.size():
			point_age[i] += 5*delta
			var rand_vector := Vector2( randf_range(-wild_speed, wild_speed), randf_range(-wild_speed, wild_speed) )
			trail_points[i] += rand_vector * wildness * point_age[i]
	else:
		tick += delta

	for i in trail_points.size():
		real_points.append(trail_points[i] - start)
	points = real_points



func add_trail_point(point_pos:Vector2):
	#if trail_points.size() > 0 and point_pos.distance_to(trail_points[-1]) < min_spawn_distance:
		#return
	point_age.append(0.0)
	trail_points.append(point_pos)
