class_name Command
extends Block

@export var detect_range:float
var detect_area:Area2D
var targets:=[]
var traverse:Array

func _ready():
	super._ready()
	generate_detection_area()

func _process(delta):
	super._process(delta)
	if not functioning:
		return
	if parent_vehicle:
		targeting()

func targeting():
	var detected_bodies = detect_area.get_overlapping_bodies()
	var detected_targets = []
	if detected_bodies.size() > 0:
		for body in detected_bodies:
			if body is Block:
				if not body in get_parent_vehicle().blocks:
					if body.get_parent_vehicle():
						var their_side = body.get_parent_vehicle().get_groups()
						var our_side = self.get_parent_vehicle().get_groups()
						if not has_common_element(our_side, their_side):
							detected_targets.append(body)
	
	targets = detected_targets


func generate_detection_area():
	# Get or create Area2D
	detect_area = Area2D.new()
	add_child(detect_area)
	if traverse:
		var segments: int = 32
		var start_angle = deg_to_rad(traverse[0]-90)
		var end_angle = deg_to_rad(traverse[-1]-90)
		var points: PackedVector2Array = [Vector2.ZERO]
		var collision_polygon = CollisionPolygon2D.new()
		
		for i in range(segments + 1):
			var t = i / float(segments)
			var angle = lerp(start_angle, end_angle, t)
			points.append(Vector2(cos(angle), sin(angle)) * detect_range)

		collision_polygon.polygon = points
		detect_area.add_child(collision_polygon)
	else:
		var collision_shape = CollisionShape2D.new()
		var circle = CircleShape2D.new()
		circle.radius = detect_range
		collision_shape.shape = circle
		detect_area.add_child(collision_shape)


func has_common_element(a1: Array, a2: Array) -> bool:
	for item in a1:
		if a2.has(item):
			return true
	return false
