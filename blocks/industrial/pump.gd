extends Block

const HITPOINT:float = 400
const WEIGHT:float = 200
const BLOCK_NAME:String = 'pump'
const TYPE:= "Industrial"
const SIZE:= Vector2(1, 1)

var description := "存储燃料供发动机使用"

var on:bool = true
var pumping:bool = false
var connected_fueltanks:Array[LiquidTank] = []
var pump_speed:= 50.0 #kg
var liquid_on_tile:= ""

# visual effect
var window_color:= Color(0, 0, 0)
var window_alpha:= 0.0
var liquid_color:Dictionary[String,Color] = {
	"crude_oil":Color(0.227, 0.094, 0.569),
}

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	type = TYPE
	size = SIZE

func _process(delta: float) -> void:
	super._process(delta)
	if on and map:
		pump_liquid(delta)
	update_pump_window(delta)

func pump_liquid(delta):
	var map_pos = map.wall.local_to_map(global_position)
	var celldata = map.wall.get_celldata(map_pos)
	if not celldata:
		liquid_on_tile = ""
		pumping = false
		return
	if TileDB.get_tile(celldata["matter"])["phase"] != "liquid":
		liquid_on_tile = ""
		pumping = false
		return
	liquid_on_tile = celldata["matter"]
	var speed_left = pump_speed * delta
	for tank:LiquidTank in find_all_connected_fueltank():
		if tank.accept_liquid(liquid_on_tile):
			var available_amount = tank.available_space()
			if available_amount == 0:
				continue
			var pump_amount = min(available_amount, speed_left)
			map.wall.remove_liquid(map_pos, pump_amount)
			tank.add_liquid(liquid_on_tile,pump_amount)
			speed_left -= pump_amount
		if speed_left == 0:
			pumping = true
		else:
			pumping = false

func find_all_connected_fueltank():
	connected_fueltanks.clear()
	for block in get_all_connected_blocks():
		if block is LiquidTank:
			connected_fueltanks.append(block)
	return connected_fueltanks


func update_pump_window(delta):
	if liquid_on_tile == "":
		window_alpha = clamp(window_alpha - delta, 0.0, 1.0)
	else:
		window_color = liquid_color[liquid_on_tile]
		window_alpha = clamp(window_alpha + delta, 0.0, 1.0)
	if pumping:
		$AnimationPlayer.play("pumping")
	else:
		$AnimationPlayer.pause()
	$Sprite2D2.modulate = Color(
		window_color.r,
		window_color.g,
		window_color.b,
		window_alpha
		)
