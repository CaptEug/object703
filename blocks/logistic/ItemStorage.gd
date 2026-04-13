class_name ItemStorage
extends Block

@export var supply_port: Vector2i = Vector2i.ZERO
@export var accept: Array[String] = []   # empty = accept all items
@export var max_load: int = 100

# item_name -> count
var items: Dictionary = {}


#func _physics_process(delta: float) -> void
	#if vehicle:
		#print("ITEMS: ", items, " / ", get_total_load(), " / ", max_load)


func get_total_load() -> float:
	var total := 0.0
	
	for item_name in items.keys():
		var count: int = items[item_name]
		var w : int = ItemDB.get_item(item_name)["weight"]
		total += count * w
	
	return total


func get_free_load() -> float:
	return max(0.0, max_load - get_total_load())


# =========================
# BASIC QUERY
# =========================

func accepts_item(item_name: String) -> bool:
	return accept.is_empty() or accept.has(ItemDB.get_item(item_name)["type"])


func get_item_count(item_name: String) -> int:
	return int(items.get(item_name, 0))


func has_item(item_name: String, amount: int) -> bool:
	if amount <= 0:
		return true
	return get_item_count(item_name) >= amount


# =========================
# ADD ITEM
# =========================

func add_item(item_name: String, amount: int) -> int:
	if amount <= 0:
		return 0
	if not accepts_item(item_name):
		return 0
	
	var weight : int = ItemDB.get_item(item_name)["weight"]
	if weight <= 0:
		return 0   # invalid item
	
	var free_load := get_free_load()
	if free_load <= 0:
		return 0
	
	# how many units can fit by weight
	var max_by_weight := int(floor(free_load / weight))
	if max_by_weight <= 0:
		return 0
	
	var accepted := mini(amount, max_by_weight)
	
	items[item_name] = get_item_count(item_name) + accepted
	
	return accepted


func take_item(item_name: String, amount: int) -> int:
	if amount <= 0:
		return 0
	
	var stored := get_item_count(item_name)
	if stored <= 0:
		return 0
	
	var taken := mini(amount, stored)
	var left := stored - taken
	
	if left <= 0:
		items.erase(item_name)
	else:
		items[item_name] = left
	
	return taken
