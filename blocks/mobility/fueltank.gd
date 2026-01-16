class_name Fueltank
extends Cargo

const ACCEPT:= ["fuel"]
const FUEL_PACK_CAPACITY: float = 100.0

var current_fuel_pack_remaining: float = 0.0
var current_fuel_pack_slot: int = -1

func _ready():
	super._ready()
	clear_all()
	add_item("gas", 10)
	if get_gas_count() > 0:
		start_new_fuel_pack()

func has_fuel() -> bool:
	return get_gas_count() > 0

func get_gas_count() -> int:
	var total = 0
	for i in range(slot_count):
		var item = get_item(i)
		if not item.is_empty() and item["id"] == "gas":
			total += item["count"]
	return total

func start_new_fuel_pack() -> bool:
	for i in range(slot_count):
		var item = get_item(i)
		if not item.is_empty() and item["id"] == "gas" and item["count"] > 0:
			current_fuel_pack_slot = i
			current_fuel_pack_remaining = FUEL_PACK_CAPACITY
			return true
	return false

func consume_current_fuel_pack():
	if current_fuel_pack_slot >= 0:
		var item = get_item(current_fuel_pack_slot)
		if not item.is_empty() and item["id"] == "gas":
			item["count"] -= 1
			if item["count"] <= 0:
				set_item(current_fuel_pack_slot, {})
			emit_signal("inventory_changed", self)
	
	current_fuel_pack_slot = -1
	current_fuel_pack_remaining = 0.0

func use_fuel(power: float, delta: float) -> bool:
	if current_fuel_pack_remaining <= 0 and not has_fuel():
		return false
	
	if current_fuel_pack_remaining <= 0:
		if not start_new_fuel_pack():
			return false
	
	var fuel_needed = power * delta

	
	if fuel_needed <= current_fuel_pack_remaining:
		current_fuel_pack_remaining -= fuel_needed
		return true
	else:
		var remaining_power = power - (current_fuel_pack_remaining / delta)
		current_fuel_pack_remaining = 0
		consume_current_fuel_pack()
		return use_fuel(remaining_power, delta)

func get_total_fuel() -> float:
	var total_gas = get_gas_count()
	return (total_gas * FUEL_PACK_CAPACITY) + current_fuel_pack_remaining

func get_fuel_percentage() -> float:
	if current_fuel_pack_slot >= 0:
		return current_fuel_pack_remaining / FUEL_PACK_CAPACITY
	return 0.0

func add_fuel_packs(count: int) -> void:
	add_item("gas", count)

func add_item(id: String, count: int) -> bool:
	var item_info = ItemDB.get_item(id)
	if not item_info:
		return false
	
	var tag = item_info.get("tag", "")
	if tag not in ACCEPT and "ALL" not in ACCEPT:
		return false
	
	return super.add_item(id, count)
