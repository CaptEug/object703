extends Control

@onready var section_container = $ScrollContainer/VBoxContainer
@export var storage_section_scene: PackedScene = preload("res://ui/inventory_panel.tscn")
@export var slot_scene: PackedScene = preload("res://ui/cargo_slot.tscn")

var current_tank: Vehicle = null

func open_inventory(tank: Vehicle):
	current_tank = tank
	refresh_inventory()
	
func toggle_inventory(tank: Vehicle):
	visible = not visible
	if visible:
		open_inventory(tank)

func close_inventory():
	visible = false

func refresh_inventory():
	clear_container(section_container)  # 清空旧的区块
	if not current_tank:
		return
	# 遍历坦克上的 blocks（或专门筛选 storage blocks）
	for block in current_tank.blocks:
		# 判断这个 block 是否是存储方块
		var slot_count = block.get("slot_count")
		if slot_count != null:
			add_storage_section(block)
	# 如果你有 panel 尺寸更新函数，可以延迟调用以保证布局完成
	call_deferred("update_panel_size")  # 可选：如果实现了 update_panel_size
			

# 清空容器子节点（推荐）
func clear_container(container: Node) -> void:
	var children = container.get_children() # 获取快照数组
	for child in children:
		child.queue_free()


func add_storage_section(block) -> void:
	var section = storage_section_scene.instantiate()
	var title_label: Label = section.get_node("VBoxContainer/Label")
	var grid: GridContainer = section.get_node("VBoxContainer/GridContainer")

	title_label.text = "%s (%d slots)" % [block.block_name, int(block.slot_count)]

	# 清空 grid（保险起见）
	clear_container(grid)

	# 设置列数（示例：最多 6 列）
	grid.columns = min(int(block.slot_count), 6)

	for i in range(int(block.slot_count)):
		var s = slot_scene.instantiate()
		# 如果 slot 支持 set_index / set_item
		if s.has_method("set_index"):
			s.set_index(i)
		var item = null
		if block.has_method("get_item"):
			item = block.get_item(i)
		elif "inventory" in block:
			item = block.inventory[i] if i < block.inventory.size() else null
		if item != null and s.has_method("set_item"):
			s.set_item(item)
		grid.add_child(s)

	section_container.add_child(section)
