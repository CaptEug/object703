extends Control

@onready var section_container = $ScrollContainer/VBoxContainer
@export var storage_section_scene: PackedScene = preload("res://ui/inventory/storage_section.tscn")
@export var slot_scene: PackedScene = preload("res://ui/inventory/cargo_slot.tscn")

var current_tank: Vehicle = null
var block_to_section := {}  # 记录每个 block -> section 的映射

# ============================================================
# 面板控制
# ============================================================
			
func open_inventory(tank: Vehicle):
	current_tank = tank
	refresh_inventory()
	if not current_tank.is_connected("cargo_changed", Callable(self, "_on_cargo_changed")):
		current_tank.connect("cargo_changed", Callable(self, "_on_cargo_changed"))
	visible = true

func toggle_inventory(tank: Vehicle):
	if visible:
		close_inventory()
	else:
		open_inventory(tank)

func close_inventory():
	visible = false
	current_tank = null
	clear_container(section_container)
	block_to_section.clear()

# ============================================================
# 主刷新逻辑
# ============================================================

func refresh_inventory():
	clear_container(section_container)
	block_to_section.clear()
	if not current_tank:
		return
	for block in current_tank.blocks:
		if block is Cargo:
			add_storage_section(block)

# ============================================================
# 区块构建
# ============================================================

func add_storage_section(block: Cargo) -> void:
	var section = storage_section_scene.instantiate()
	var title_label: Label = section.get_node("Label")
	var grid: GridContainer = section.get_node("GridContainer")

	title_label.text = "%s (%d slots)" % [block.block_name, int(block.slot_count)]

	grid.columns = min(int(block.slot_count), 6)
	clear_container(grid)

	for i in range(int(block.slot_count)):
		var slot = slot_scene.instantiate()
		slot.slot_index = i
		slot.storage_ref = block
		slot.accept = block.ACCEPT

		grid.add_child(slot)  # ✅ 先加入场景树，触发 _ready()

		var item = block.get_item(i)
		if slot.has_method("set_item"):
			slot.call_deferred("set_item", item)  # ✅ 延迟调用
		else:
			slot.item_data = item
			slot.call_deferred("update_slot_display")

	section_container.add_child(section)
	block_to_section[block] = section

	# ✅ 监听 Cargo 的 inventory_changed 信号
	if not block.is_connected("inventory_changed", Callable(self, "_on_inventory_changed")):
		block.connect("inventory_changed", Callable(self, "_on_inventory_changed"))

# ============================================================
# 当某个 Cargo 更新库存时，仅刷新对应区块
# ============================================================

func _on_inventory_changed(block: Cargo) -> void:
	if not block_to_section.has(block):
		add_storage_section(block)
		print("added new section")
		return
	var section = block_to_section[block]
	if not is_instance_valid(section):
		print("❌ No section found for", block)
		return

	var grid: GridContainer = section.get_node("GridContainer")
	clear_container(grid)

	grid.columns = min(int(block.slot_count), 6)
	for i in range(int(block.slot_count)):
		var slot = slot_scene.instantiate()
		slot.slot_index = i
		slot.storage_ref = block

		grid.add_child(slot)  # ✅ 先加入场景树，触发 _ready()

		var item = block.get_item(i)
		print("getted item:", item)
		if slot.has_method("set_item"):
			slot.call_deferred("set_item", item)  # ✅ 延迟调用
		else:
			slot.item_data = item
			slot.call_deferred("update_slot_display")

func _on_cargo_changed():
	refresh_inventory()
	pass

# ============================================================
# 工具函数
# ============================================================

func clear_container(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()

func _on_close_button_pressed() -> void:
	close_inventory()

	
func _test_take_item(current_tank) -> void:
	var tank = current_tank
	for block in tank.blocks:
		if block is Cargo:
			var scrap = block.take_item("scrap", 1)
			print("item_taken", scrap)
			return
	
