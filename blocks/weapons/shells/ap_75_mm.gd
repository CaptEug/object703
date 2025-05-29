extends Shell

const WEIGHT:float = 3
var shell_name:String = '75mm armorpiercing'
var kenetic_damage:int = 150

@onready var trail = $Line2D
var trail_points := []

func update_trail(delta):
	trail_points.append(global_position)
	if trail_points.size() > 5:
		trail_points.pop_front()
	var real_points = []
	var start = trail_points[-1]
	for i in trail_points.size():
		real_points.append(trail_points[i] - start)
	trail.points = real_points

# Called when the node enters the scene tree for the first time.
func _ready():
	pass


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	update_trail(delta)


func _on_area_2d_body_entered(block:Block):
	var block_hp = block.current_hp
	var momentum:Vector2 = WEIGHT * linear_velocity
	block.apply_impulse(momentum)
	block.damage(kenetic_damage)
	kenetic_damage -= block_hp
	if kenetic_damage <= 0:
		queue_free()
