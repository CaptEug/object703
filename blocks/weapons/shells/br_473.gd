extends Shell

const SHELL_NAME:String = '122mm BR-473'
const TYPE:String = 'SAP'
const WEIGHT:float = 25
const LIFETIME:float = 1.5
const KENETIC_DAMAGE:int = 2000
const MAX_EXPLOSIVE_DAMAGE:int = 999
const EXPLOSION_RADIUS:int = 50

func init():
	shell_name = SHELL_NAME
	type = TYPE
	weight = WEIGHT
	lifetime = LIFETIME
	kenetic_damage = KENETIC_DAMAGE
	max_explosive_damage = MAX_EXPLOSIVE_DAMAGE
	explosion_radius = EXPLOSION_RADIUS
	explosion_area = $ExplosionArea
	explosion_shape = $ExplosionArea/CollisionShape2D
	shell_body = $Area2D
	trail = $Trail
