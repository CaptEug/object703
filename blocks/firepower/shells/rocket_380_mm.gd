extends Shell

const SHELL_NAME:String = '38cm Rocket'
const TYPE:String = 'HE'
const WEIGHT:float = 350
const LIFETIME:float = 5
const KENETIC_DAMAGE:int = 50
const MAX_EXPLOSIVE_DAMAGE:int = 3000
const EXPLOSION_RADIUS:int = 100
const MAX_THRUST:float = 150000
const ACCELERATION:float = 100000


func _init():
	shell_name = SHELL_NAME
	type = TYPE
	weight = WEIGHT
	lifetime = LIFETIME
	kenetic_damage = KENETIC_DAMAGE
	max_explosive_damage = MAX_EXPLOSIVE_DAMAGE
	explosion_radius = EXPLOSION_RADIUS
	max_thrust = MAX_THRUST
	acceleration = ACCELERATION
