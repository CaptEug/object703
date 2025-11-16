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
	for i in range(slot_count):
		inventory[i] = {}
	add_item("57mmAP", 10)
	add_item("PZGR75", 10)
	add_item("122mmAPHE", 10)
	add_item("380mmrocket", 10)
	#self.connect("inventory_changed", Callable(%InventoryPanel, "_on_inventory_changed"))
	#print("connected to inventory:",self.is_connected("inventory_changed", Callable(%InventoryPanel, "_on_inventory_changed")))
	#emit_signal("inventory_changed",self)
	

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
	
	for i in range(len(inventory)):
		if inventory[i].is_empty():
			continue
		if inventory[i]["id"] == id:
			inventory[i]["count"] += count
			return true
	
	var item_data = {"id": id, "count": count}
	for i in range(len(inventory)):
		if inventory[i].is_empty():
			return place_item(i, item_data)
	
	return false


func take_item(id: String, count: int) -> bool:
	var total_item_stored:int = 0
	var count_remain = count
	#Check total numer in inventory
	for i in range(len(inventory)):
		if inventory[i].is_empty():
			continue
		elif inventory[i]["id"] == id:
			total_item_stored += inventory[i]["count"]
	if total_item_stored < count:
		return false
	
	for i in range(len(inventory)):
		if inventory[i].is_empty():
			continue
		elif inventory[i]["id"] == id:
			if inventory[i]["count"] >= count_remain:
				inventory[i]["count"] -= count_remain
				if inventory[i]["count"] == 0:
					inventory[i] = {}
				emit_signal("inventory_changed", self)
				return true
			else:
				count_remain -= inventory[i]["count"]
				inventory[i] = {}
				emit_signal("inventory_changed", self)
	
	return false

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
	
