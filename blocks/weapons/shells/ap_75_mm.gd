extends Shell

const WEIGHT:float = 3
var shell_name:String = '75mm armorpiercing'
var kenetic_damage:int = 150
# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func _on_area_2d_body_entered(block:Block):
	var block_hp = block.current_hp
	var momentum:Vector2 = WEIGHT * linear_velocity
	block.apply_impulse(momentum)
	block.damage(kenetic_damage)
	kenetic_damage -= block_hp
	if kenetic_damage <= 0:
		queue_free()
