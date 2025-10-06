class_name Cargo
extends Block

var inventory:Array = []
var accept:Array = []
@export var slot_count := 20


func _ready():
	# Initialize empty slots
	inventory.resize(slot_count)
	for i in range(slot_count):
		inventory[i] = null  # null means empty slot


func _process(delta):
	pass


func set_item(slot_index: int, item_data: Dictionary) -> bool:
	if slot_index < 0 or slot_index >= slot_count:
		return false
	inventory[slot_index] = item_data
	return true

func get_item(slot_index: int) -> Dictionary:
	return inventory[slot_index]
