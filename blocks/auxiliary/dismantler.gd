extends Block

const HITPOINT:float = 800
const WEIGHT:float = 1000
const BLOCK_NAME:String = 'dismantler'
const SIZE:= Vector2(2, 2)
const TYPE:= 'Auxiliary'

var description := ""
var outline_tex := preload("res://assets/outlines/dismantler_outline.png")

var inventory:Array = []
var on:bool
var dmg:= 15
var contacted_blocks:Array[Block] = []
var connected_cargo:Array[Cargo] = []
@onready var saw:RigidBody2D = $Saw

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	type = TYPE


func _physics_process(_delta):

	print("CONNECTED BLOCKS:", connected_blocks)
	print("JOINTED CONNECTED BLOCKS:", joint_connected_blocks.values())

	if not functioning:
		on = false
		return
	if on:
		saw.apply_torque(1000)
		damage_contacted_blocks()


func _unhandled_input(event: InputEvent) -> void:
	if get_parent_vehicle() and functioning:
		var control_method = get_parent_vehicle().control.get_method()
		if control_method == "manual_control":
			if event.is_action("FIRE_MAIN"):  # only respond to FIRE_MAIN events
				on = event.is_action_pressed("FIRE_MAIN")  # true on press, false on release

func damage_contacted_blocks():
	for block in contacted_blocks:
		var block_hp = block.current_hp
		if block_hp >= 0:
			var damage_to_deal = min(dmg, block_hp)
			if block_hp <= dmg:
				gain_scrap(block)
			block.damage(damage_to_deal)

func gain_scrap(block):
	var _amount = block.size.x * block.size.y
	

func find_all_connected_cargo():
	connected_cargo.clear()
	for block in get_all_connected_blocks():
		if block is Cargo:
			connected_cargo.append(block)
	return connected_cargo
	

func _on_saw_body_entered(block:Block):
	var vehicle_hit = block.parent_vehicle
	#check if the vehicle is not self
	if vehicle_hit == get_parent_vehicle():
		return
	
	if not contacted_blocks.has(block):
		contacted_blocks.append(block)


func _on_saw_body_exited(block:Block):
	var vehicle_hit = block.parent_vehicle
	#check if the vehicle is not self
	if vehicle_hit == get_parent_vehicle():
		return
	
	if contacted_blocks.has(block):
		contacted_blocks.erase(block)
