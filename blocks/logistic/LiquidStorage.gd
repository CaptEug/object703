class_name LiquidStorage
extends Block

signal contents_changed
signal allowed_items_changed

@export var capacity: float = 100.0
@export var stored: float = 0.0
@export var liquid: String = ""

var allowed_items: Array[String] = []

func _ready() -> void:
	super()
	reset_allowed_items()

func get_compatible_item_ids() -> Array[String]:
	return ItemDB.get_items_by_type(ItemDB.ItemType.LIQUID)

func is_item_compatible(item_id: String) -> bool:
	var item_data := ItemDB.get_item(item_id)
	return not item_data.is_empty() and item_data.get("type", -1) == ItemDB.ItemType.LIQUID

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

func accepts_item(item_id: String) -> bool:
	return is_item_compatible(item_id) and allowed_items.has(item_id)

func has_liquid(liquid_type: String, amount: float) -> bool:
	return liquid == liquid_type and stored >= amount

func get_free_space() -> float:
	return maxf(0.0, capacity - stored)

func take_liquid(liquid_type: String, amount: float) -> float:
	if amount <= 0.0 or stored <= 0.0 or liquid != liquid_type:
		return 0.0
	var taken := minf(stored, amount)
	stored -= taken
	if stored <= 0.001:
		stored = 0.0
		liquid = ""
	contents_changed.emit()
	return taken

func add_liquid(liquid_type: String, amount: float) -> float:
	if amount <= 0.0 or not accepts_item(liquid_type):
		return 0.0
	if stored <= 0.0:
		liquid = liquid_type
	if liquid != liquid_type:
		return 0.0
	var accepted := minf(get_free_space(), amount)
	if accepted > 0.0:
		stored += accepted
		contents_changed.emit()
	return accepted
