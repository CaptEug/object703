extends Tiles

const HITPOINT:float = 400
const TILE_NAME:String = 'sandstone'
const KENEMATIC_ABSORB:float = 1.0
const EXPLOSE_ABSORB:float = 1.5

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
