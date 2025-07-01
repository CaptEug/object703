extends Shell

const SHELL_NAME:String = '57mm BR-273P'
const TYPE:String = 'AP'
const WEIGHT:float = 7.2
const LIFETIME:float = 0.5
const KENETIC_DAMAGE:int = 80

func init():
	shell_name = SHELL_NAME
	type = TYPE
	weight = WEIGHT
	lifetime = LIFETIME
	kenetic_damage = KENETIC_DAMAGE
	shell_body = $Area2D
	trail = $Trail
