class_name Cargo
extends Block

signal inventory_changed(cargo: Cargo)


@export var slot_count: int = 6
@export var is_full: bool = false
var inventory: Array = [] # 每个元素是 Dictionary, eg. {"id": "iron", "count": 10, "weight": 1, "icon": Texture2D}
var accept: Array = []  # 可以存放的物品类型约束（暂留）
var max_load: float = false

func _ready():
	super._ready()
	initialize_inventory()

# ============================================================
# 初始化 / 安全访问
# ============================================================
func initialize_inventory():
	inventory.resize(slot_count)
	for i in range(slot_count):
		inventory[i] = {}
	set_item(0, test_generate_scrap())

func get_item(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= slot_count:
		return {}
	var item = inventory[slot_index]
	if item == null:
		return {}
	return item

func set_item(slot_index: int, item_data: Dictionary) -> bool:
	if slot_index < 0 or slot_index >= slot_count and check_overload():
		return false
	inventory[slot_index] = item_data
	print("📦 Set item at", slot_index, ":", item_data)
	return true
	
func finalize_changes():
	emit_signal("inventory_changed", self)

# ============================================================
# 物品交互接口（供 UI 调用）
# ============================================================
func pick_item(slot_index: int) -> Dictionary:
	var item = get_item(slot_index)
	if item.is_empty():
		return {}
	inventory[slot_index] = {}
	emit_signal("inventory_changed", self)
	return item

func place_item(slot_index: int, item: Dictionary) -> bool:
	if slot_index < 0 or slot_index >= slot_count:
		return false
	if inventory[slot_index].is_empty():
		inventory[slot_index] = item
	else:
		# 可堆叠：相同id则叠加数量
		if inventory[slot_index].get("id", "") == item.get("id", ""):
			inventory[slot_index]["count"] += item.get("count", 1)
		else:
			return false
	emit_signal("inventory_changed", self)
	return true

func split_item(slot_index: int) -> Dictionary:
	var item = get_item(slot_index)
	if item.is_empty() or item.get("count", 1) <= 1:
		return {}
	var half = int(item["count"] / 2)
	item["count"] -= half
	var new_item = item.duplicate()
	new_item["count"] = half
	emit_signal("inventory_changed", self)
	return new_item
	
# ✅ 自动添加到第一个空位
func add_item(item_data: Dictionary) -> bool:
	for i in range(slot_count):
		return place_item(i, item_data)
	return false

func clear_all():
	for i in range(slot_count):
		inventory[i] = {}
	emit_signal("inventory_changed", self)

# ============================================================
# 可扩展：类型限制或容量控制
# ============================================================
func can_accept_item(item: Dictionary) -> bool:
	if accept.is_empty():
		return true
	return item.get("type", "") in accept
	
func check_overload() -> bool:
	var is_overload = calculate_total_weight() >= max_load
	is_full = is_overload
	return is_overload
# ============================================================
# 工具
# ============================================================
func calculate_total_weight() -> float:
	var total_weight = 0
	for i in inventory:
		total_weight += i.count * i.weight
	return total_weight
	
func test_generate_scrap() -> Dictionary:
	var texture: Texture2D = load("res://assets/icons/scrap.png")
	return {"id": "scrap", "count": 10, "weight": 1, "icon": texture}
