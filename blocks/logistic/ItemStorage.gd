class_name ItemStorage
extends ExpandableBlock

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


func has_information_panel() -> bool:
	return true


func get_union_key() -> String:
	return "%s:item:%d" % [scene_file_path, storage_kind]


func get_save_state() -> Dictionary:
	var result := {
		"items": items.duplicate(true),
	}
	if not is_default_allowed_items():
		result["allowed_items"] = allowed_items.duplicate()
	return result


func apply_save_state(state: Dictionary) -> void:
	var saved_items: Variant = state.get("items")
	if saved_items is Dictionary:
		items.clear()
		for item_value: Variant in saved_items:
			var item_name := str(item_value)
			var amount := maxi(int(saved_items[item_value]), 0)
			if amount > 0 and is_item_compatible(item_name):
				items[item_name] = amount
	var saved_allowed: Variant = state.get("allowed_items")
	if saved_allowed is Array:
		set_allowed_items(saved_allowed)
	else:
		reset_allowed_items()
	contents_changed.emit()


func _scale_union_capacity(unit_count: int) -> void:
	max_load *= unit_count


func _merge_union_data(members: Array) -> void:
	var combined_max_load := 0
	var combined_items := {}
	var allowed_union: Array[String] = []
	for value: Variant in members:
		var storage := value as ItemStorage
		if storage == null:
			continue
		combined_max_load += storage.max_load
		for item_name: String in storage.items:
			combined_items[item_name] = (
				int(combined_items.get(item_name, 0))
				+ storage.get_item_count(item_name)
			)
		for item_name: String in storage.allowed_items:
			if not allowed_union.has(item_name):
				allowed_union.append(item_name)
	allowed_union.sort()
	max_load = combined_max_load
	items = combined_items
	allowed_items = allowed_union
	contents_changed.emit()
	allowed_items_changed.emit()

func get_accepted_item_type() -> int:
	if storage_kind == StorageKind.DUMP:
		return ItemDB.ItemType.MINERAL
	return ItemDB.ItemType.MATERIAL

func get_compatible_item_names() -> Array[String]:
	return ItemDB.get_items_by_type(get_accepted_item_type())

func is_item_compatible(item_name: String) -> bool:
	var item_data := ItemDB.get_item_by_name(item_name)
	return not item_data.is_empty() and item_data.get("type", -1) == get_accepted_item_type()

func reset_allowed_items() -> void:
	allowed_items = get_compatible_item_names()
	allowed_items_changed.emit()

func set_allowed_items(item_names: Array) -> void:
	var validated: Array[String] = []
	for value: Variant in item_names:
		if value is String and is_item_compatible(value) and not validated.has(value):
			validated.append(value)
	validated.sort()
	allowed_items = validated
	allowed_items_changed.emit()

func add_allowed_item(item_name: String) -> bool:
	if not is_item_compatible(item_name) or allowed_items.has(item_name):
		return false
	allowed_items.append(item_name)
	allowed_items.sort()
	allowed_items_changed.emit()
	return true

func remove_allowed_item(item_name: String) -> bool:
	var index := allowed_items.find(item_name)
	if index < 0:
		return false
	allowed_items.remove_at(index)
	allowed_items_changed.emit()
	return true

func is_default_allowed_items() -> bool:
	var current := allowed_items.duplicate()
	var default_items := get_compatible_item_names()
	current.sort()
	default_items.sort()
	return current == default_items

func get_total_load() -> float:
	var total := 0.0
	for item_name: String in items:
		total += int(items[item_name]) * float(ItemDB.get_item_by_name(item_name).get("weight", 0.0))
	return total

func get_free_load() -> float:
	return maxf(0.0, max_load - get_total_load())

func accepts_item(item_name: String) -> bool:
	return is_item_compatible(item_name) and allowed_items.has(item_name)

func get_item_count(item_name: String) -> int:
	return int(items.get(item_name, 0))

func has_item(item_name: String, amount: int) -> bool:
	return amount <= 0 or get_item_count(item_name) >= amount

func add_item(item_name: String, amount: int) -> int:
	if amount <= 0 or not accepts_item(item_name):
		return 0
	var weight := float(ItemDB.get_item_by_name(item_name).get("weight", 0.0))
	if weight <= 0.0:
		return 0
	var accepted := mini(amount, int(floor(get_free_load() / weight)))
	if accepted > 0:
		items[item_name] = get_item_count(item_name) + accepted
		contents_changed.emit()
	return accepted

func take_item(item_name: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var taken := mini(amount, get_item_count(item_name))
	if taken <= 0:
		return 0
	var left := get_item_count(item_name) - taken
	if left <= 0:
		items.erase(item_name)
	else:
		items[item_name] = left
	contents_changed.emit()
	return taken
