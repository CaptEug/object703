extends Panel

@onready var textlabel: RichTextLabel = $RichTextLabel
@onready var grid_container: GridContainer = $GridContainer

@export var padding: Vector2 = Vector2(16, 32)

var _last_block: Node = null

func _ready() -> void:
	visible = false
	grid_container.visible = false


func _physics_process(_delta: float) -> void:
	var mouse_pos = get_tree().current_scene.get_local_mouse_position()
	var space_state = get_world_2d().direct_space_state

	var query := PhysicsPointQueryParameters2D.new()
	query.position = mouse_pos
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var results = space_state.intersect_point(query)
	if results.size() > 0:
		var body = results[0].collider
		if body is Block:
			visible = true
			global_position = get_viewport().get_mouse_position() + Vector2(16, 16)

			# --- 基本信息 ---
			var vehicle = null
			if body.has_method("get_parent_vehicle"):
				vehicle = body.get_parent_vehicle() as Vehicle
			if vehicle:
				textlabel.text = body.block_name
			else:
				textlabel.text = body.block_name + ": debris"

			# --- Cargo 特殊内容 ---
			# 尝试按优先级取 items：
			var items: Array = []
			var cargo_inventory = body.get("inventory")  # Object.get(property_name) 在属性不存在时通常返回 null
			if cargo_inventory != null and cargo_inventory is Array:
				items = cargo_inventory
			if items.size() > 0:
				_update_cargo_items(items)
			else:
				_clear_grid()

			call_deferred("update_panel_size")
			_last_block = body
			return

	# ---- 鼠标移出或未检测到 ----
	if visible:
		visible = false
	_clear_grid()
	call_deferred("update_panel_size")
	_last_block = null


# 清空 grid（无 cargo 或空内容时）
func _clear_grid() -> void:
	for c in grid_container.get_children():
		c.queue_free()
	grid_container.visible = false


# 显示 cargo 内物品（仅显示 count > 0 的）
func _update_cargo_items(items: Array) -> void:
	# 清空旧格子
	for c in grid_container.get_children():
		c.queue_free()

	# 过滤非空物品
	var non_empty: Array = []
	for item in items:
		if item is Dictionary and item.has("count") and item.count > 0:
			non_empty.append(item)

	if non_empty.is_empty():
		grid_container.visible = false
		return

	grid_container.columns = min(non_empty.size(), 6)
	grid_container.visible = true
	# 创建显示格
	for item_data in non_empty:
		var slot = _create_item_slot(item_data)
		grid_container.add_child(slot)

	call_deferred("update_panel_size")


# 动态调整 panel 尺寸
func update_panel_size() -> void:
	var text_size: Vector2 = textlabel.get_size()
	var grid_size: Vector2 = Vector2.ZERO
	if grid_container.visible:
		grid_size = grid_container.get_size()

	var content_width = max(text_size.x, grid_size.x)
	var content_height = text_size.y
	if grid_container.visible:
		content_height += grid_size.y

	size = Vector2(content_width, content_height) + padding

func _create_item_slot(item_data):
	var slot = Control.new()
	slot.custom_minimum_size = Vector2(32, 32)

	# 如果你原来在 .tscn 里有个 TextureRect:
	var icon = TextureRect.new()
	icon.texture = item_data.icon
	slot.add_child(icon)

	# 可选：添加数量标签
	var label = Label.new()
	label.text = str(item_data.count)
	label.position = Vector2(16, 16)
	slot.add_child(label)

	return slot
