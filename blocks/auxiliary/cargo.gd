class_name Cargo
extends Block

signal inventory_changed(cargo: Cargo)

@export var slot_count: int = 6
@export var is_full: bool = false
@export var ui_ref: Node = null
var inventory: Array = [] # 每个元素是 Dictionary, eg. {"id": "iron", "count": 10}
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
	for item_index in range(slot_count):
		inventory[item_index] = {}
	add_item("57mmAP", 10)
	add_item("PZGR75", 10)
	add_item("122mmAPHE", 10)
	add_item("380mmrocket", 10)
	add_item("gas", 10)
	

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

func add_item(id: String, count: int) -> bool:
	if ItemDB.get_item(id)["tag"] not in self.ACCEPT and "ALL" not in self.ACCEPT:
		return false 
	
	var item_data = {"id": id, "count": count}
	
	for item_index in range(len(inventory)):
		if inventory[item_index].is_empty():
			inventory[item_index] = item_data
			emit_signal("inventory_changed", self)
			return true
		elif inventory[item_index]["id"] == id:
			inventory[item_index]["count"] += count
			emit_signal("inventory_changed", self)
			return true
	
	return false

func take_item(id: String, count: int) -> bool:
	var total_item_stored = 0
	var count_remain = count
	#Check total numer in inventory
	for item_index in range(len(inventory)):
		if inventory[item_index].is_empty():
			continue
		elif inventory[item_index]["id"] == id:
			total_item_stored += inventory[item_index]["count"]
	if total_item_stored < count:
		return false
	
	for item_index in range(len(inventory)):
		if inventory[item_index].is_empty():
			continue
		elif inventory[item_index]["id"] == id:
			if inventory[item_index]["count"] >= count_remain:
				inventory[item_index]["count"] -= count_remain
				if inventory[item_index]["count"] == 0:
					inventory[item_index] = {}
				emit_signal("inventory_changed", self)
				return true
			else:
				count_remain -= inventory[item_index]["count"]
				inventory[item_index] = {}
				emit_signal("inventory_changed", self)
	
	return false

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

func clear_all():
	for item_index in range(slot_count):
		inventory[item_index] = {}
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
	for item_index in inventory:
		total_weight += item_index.count * item_index.weight
	return total_weight
	
