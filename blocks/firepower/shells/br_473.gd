extends Shell

const SHELL_NAME:String = '122mm BR-473'
const TYPE:String = 'SAP'
const WEIGHT:float = 25
const LIFETIME:float = 1.5
const KENETIC_DAMAGE:int = 400
const MAX_EXPLOSIVE_DAMAGE:int = 300
const EXPLOSION_RADIUS:int = 30

func _init():
	shell_name = SHELL_NAME
	type = TYPE
	weight = WEIGHT
	lifetime = LIFETIME
	kenetic_damage = KENETIC_DAMAGE
	max_explosive_damage = MAX_EXPLOSIVE_DAMAGE
	explosion_radius = EXPLOSION_RADIUS
