extends Shell

const SHELL_NAME:String = '75mm armorpiercing'
const WEIGHT:float = 3
const LIFETIME:float = 2
const KENETIC_DAMAGE:int = 150

func init():
	shell_name = SHELL_NAME
	weight = WEIGHT
	kenetic_damage = KENETIC_DAMAGE
	shell_body = $Area2D
	trail = $Trail
