extends Cargo

const HITPOINT:float = 400
const WEIGHT:float = 100
const BLOCK_NAME:String = 'small cargo'
const SIZE:= Vector2(1, 1)
const MAX_LOAD:float = 2000
const TYPE:= 'Auxiliary'
const ACCEPT:= ["ALL"]


func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	accept = ACCEPT
	size = SIZE
	type = TYPE

func _ready():
	# Initialize empty slots
	super._ready()
	inventory.resize(slot_count)
	for i in range(slot_count):
		inventory[i] = null  # null means empty slot

func set_item(slot_index: int, item_data: Dictionary) -> bool:
	if slot_index < 0 or slot_index >= slot_count:
		return false
	inventory[slot_index] = item_data
	return true

func get_item(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= slot_count:
		return {}
	if inventory[slot_index] == null:
		return {}
	return inventory[slot_index]
