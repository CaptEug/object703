class_name ItemStorage
extends Block

enum StorageKind {
	DUMP,
	CARGO,
}

signal contents_changed
signal allowed_items_changed

@export var storage_kind: StorageKind = StorageKind.CARGO
@export var max_load: int = 100

var items: Dictionary = {}
var allowed_items: Array[String] = []

func _ready() -> void:
	super()
	reset_allowed_items()
	add_item("PZGR88mm", 20)

func get_accepted_item_type() -> int:
	if storage_kind == StorageKind.DUMP:
		return ItemDB.ItemType.MINERAL
	return ItemDB.ItemType.MATERIAL

func get_compatible_item_ids() -> Array[String]:
	return ItemDB.get_items_by_type(get_accepted_item_type())

func is_item_compatible(item_id: String) -> bool:
	var item_data := ItemDB.get_item(item_id)
	return not item_data.is_empty() and item_data.get("type", -1) == get_accepted_item_type()

func reset_allowed_items() -> void:
	allowed_items = get_compatible_item_ids()
	allowed_items_changed.emit()

func set_allowed_items(item_ids: Array) -> void:
	var validated: Array[String] = []
	for value: Variant in item_ids:
		if value is String and is_item_compatible(value) and not validated.has(value):
			validated.append(value)
	validated.sort()
	allowed_items = validated
	allowed_items_changed.emit()

func add_allowed_item(item_id: String) -> bool:
	if not is_item_compatible(item_id) or allowed_items.has(item_id):
		return false
	allowed_items.append(item_id)
	allowed_items.sort()
	allowed_items_changed.emit()
	return true

func remove_allowed_item(item_id: String) -> bool:
	var index := allowed_items.find(item_id)
	if index < 0:
		return false
	allowed_items.remove_at(index)
	allowed_items_changed.emit()
	return true

func is_default_allowed_items() -> bool:
	var current := allowed_items.duplicate()
	var default_items := get_compatible_item_ids()
	current.sort()
	default_items.sort()
	return current == default_items

func get_total_load() -> float:
	var total := 0.0
	for item_id: String in items:
		total += int(items[item_id]) * float(ItemDB.get_item(item_id).get("weight", 0.0))
	return total

func get_free_load() -> float:
	return maxf(0.0, max_load - get_total_load())

func accepts_item(item_id: String) -> bool:
	return is_item_compatible(item_id) and allowed_items.has(item_id)

func get_item_count(item_id: String) -> int:
	return int(items.get(item_id, 0))

func has_item(item_id: String, amount: int) -> bool:
	return amount <= 0 or get_item_count(item_id) >= amount

func add_item(item_id: String, amount: int) -> int:
	if amount <= 0 or not accepts_item(item_id):
		return 0
	var weight := float(ItemDB.get_item(item_id).get("weight", 0.0))
	if weight <= 0.0:
		return 0
	var accepted := mini(amount, int(floor(get_free_load() / weight)))
	if accepted > 0:
		items[item_id] = get_item_count(item_id) + accepted
		contents_changed.emit()
	return accepted

func take_item(item_id: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var taken := mini(amount, get_item_count(item_id))
	if taken <= 0:
		return 0
	var left := get_item_count(item_id) - taken
	if left <= 0:
		items.erase(item_id)
	else:
		items[item_id] = left
	contents_changed.emit()
	return taken
