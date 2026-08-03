class_name LiquidStorage
extends ExpandableBlock

signal contents_changed
signal allowed_items_changed

@export var capacity: float = 100.0
@export var stored: float = 0.0
@export var liquid: String = ""

var allowed_items: Array[String] = []

func _ready() -> void:
	super()
	reset_allowed_items()
	add_liquid("petroleum", 50)


func has_information_panel() -> bool:
	return true


func get_union_key() -> String:
	return "%s:liquid" % scene_file_path


func get_save_state() -> Dictionary:
	var result := {
		"liquid": liquid,
		"stored": stored,
	}
	if not is_default_allowed_items():
		result["allowed_items"] = allowed_items.duplicate()
	return result


func apply_save_state(state: Dictionary) -> void:
	var saved_liquid := str(state.get("liquid", ""))
	var saved_stored := clampf(
		float(state.get("stored", 0.0)),
		0.0,
		capacity
	)
	if (
		saved_stored > 0.001
		and is_item_compatible(saved_liquid)
	):
		liquid = saved_liquid
		stored = saved_stored
	else:
		liquid = ""
		stored = 0.0
	var saved_allowed: Variant = state.get("allowed_items")
	if saved_allowed is Array:
		set_allowed_items(saved_allowed)
	else:
		reset_allowed_items()
	contents_changed.emit()


func can_union_members(members: Array) -> bool:
	var contained_liquid := ""
	for value: Variant in members:
		var storage := value as LiquidStorage
		if (
			storage == null
			or storage.stored <= 0.001
			or storage.liquid.is_empty()
		):
			continue
		if contained_liquid.is_empty():
			contained_liquid = storage.liquid
		elif contained_liquid != storage.liquid:
			return false
	return true


func _scale_union_capacity(unit_count: int) -> void:
	capacity *= unit_count


func _merge_union_data(members: Array) -> void:
	var combined_capacity := 0.0
	var combined_stored := 0.0
	var combined_liquid := ""
	var allowed_union: Array[String] = []
	for value: Variant in members:
		var storage := value as LiquidStorage
		if storage == null:
			continue
		combined_capacity += storage.capacity
		combined_stored += storage.stored
		if combined_liquid.is_empty() and not storage.liquid.is_empty():
			combined_liquid = storage.liquid
		for item_name: String in storage.allowed_items:
			if not allowed_union.has(item_name):
				allowed_union.append(item_name)
	allowed_union.sort()
	capacity = combined_capacity
	stored = combined_stored
	liquid = combined_liquid if combined_stored > 0.001 else ""
	allowed_items = allowed_union
	contents_changed.emit()
	allowed_items_changed.emit()

func get_compatible_item_names() -> Array[String]:
	return ItemDB.get_items_by_type(ItemDB.ItemType.LIQUID)

func is_item_compatible(item_name: String) -> bool:
	var item_data := ItemDB.get_item_by_name(item_name)
	return not item_data.is_empty() and item_data.get("type", -1) == ItemDB.ItemType.LIQUID

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

func accepts_item(item_name: String) -> bool:
	return is_item_compatible(item_name) and allowed_items.has(item_name)

func has_liquid(liquid_name: String, amount: float) -> bool:
	return liquid == liquid_name and stored >= amount

func get_free_space() -> float:
	return maxf(0.0, capacity - stored)

func take_liquid(liquid_name: String, amount: float) -> float:
	if amount <= 0.0 or stored <= 0.0 or liquid != liquid_name:
		return 0.0
	var taken := minf(stored, amount)
	stored -= taken
	if stored <= 0.001:
		stored = 0.0
		liquid = ""
	contents_changed.emit()
	return taken

func add_liquid(liquid_name: String, amount: float) -> float:
	if amount <= 0.0 or not accepts_item(liquid_name):
		return 0.0
	if stored <= 0.0:
		liquid = liquid_name
	if liquid != liquid_name:
		return 0.0
	var accepted := minf(get_free_space(), amount)
	if accepted > 0.0:
		stored += accepted
		contents_changed.emit()
	return accepted
