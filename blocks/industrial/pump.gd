extends Block

const HITPOINT:float = 400
const WEIGHT:float = 200
const BLOCK_NAME:String = 'pump'
const TYPE:= "Industrial"
const SIZE:= Vector2(1, 1)

var description := "存储燃料供发动机使用"

var on:bool = false
var connected_fueltanks:Array[LiquidTank] = []
var pump_speed:= 50.0 #kg

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	type = TYPE
	size = SIZE

func _process(delta: float) -> void:
	super._process(delta)
	pump_liquid(delta)

func pump_liquid(delta):
	var map_pos = map.wall.local_to_map(global_position)
	var celldata = map.wall.get_celldata(map_pos)
	if not celldata:
		return
	var liquid_on_tile = celldata["matter"]
	if TileDB.get_tile(liquid_on_tile)["phase"] != "liquid":
		return
	var speed_left = pump_speed * delta
	for tank:LiquidTank in find_all_connected_fueltank():
		if tank.accept_liquid(liquid_on_tile):
			var pump_amount = min(tank.available_space(), speed_left)
			map.wall.remove_liquid(map_pos, pump_amount)
			tank.stored_amount += pump_amount
			speed_left -= pump_amount
		if speed_left == 0:
			return

func find_all_connected_fueltank():
	connected_fueltanks.clear()
	for block in get_all_connected_blocks():
		if block is LiquidTank:
			connected_fueltanks.append(block)
	return connected_fueltanks
