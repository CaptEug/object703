extends TextureRect

@onready var item_icon: TextureRect = $ItemIcon
@onready var count_label: Label = $CountLabel

@export var slot_index: int = 0
@export var storage_ref: Node = null # 指向 Cargo 节点
@export var inventory_panel_ref: Panel = null

var accept = []
var item_data: Dictionary = {}       # { "id": "iron", "count": 20}

var is_dragging := false
var drag_preview = null
var drag_offset := Vector2.ZERO
var drag_origin_pos := Vector2.ZERO
var drag_source_item: Dictionary = {}    # 当前拖拽物（独立于 item_data）
var drag_from_slot_ref: Node = null      # 源 slot（通常是 self，拆分也来自 self）
var drag_is_split: bool = false          # 是否为拆分产生的拖拽物
var slot_under_mouse = null


# ============================================================
# 初始化
# ============================================================
func _ready():
	texture = preload("res://assets/icons/item_slot.png")
	stretch_mode = STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = MOUSE_FILTER_STOP

	item_icon.expand = true
	item_icon.stretch_mode = STRETCH_KEEP_ASPECT_CENTERED
	item_icon.visible = false

	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count_label.add_theme_font_size_override("font_size", 16)
	count_label.visible = false

	add_to_group("cargo_slot")
	call_deferred("update_slot_display")


# ============================================================
# 显示逻辑
# ============================================================
func set_item(item: Dictionary) -> void:
	item_data = item
	update_slot_display()

func update_slot_display() -> void:
	if item_data.is_empty():
		hide_current_icon()
	else:
		item_icon.texture = ItemDB.get_item(item_data.get("id")).get("icon")
		item_icon.visible = true
		var count = item_data.get("count", 1)
		count_label.text = str(count)
		count_label.visible = count > 0
		if is_dragging:
			_end_drag()
		show_current_icon()


# ============================================================
# 拖放交互
# ============================================================
func _gui_input(event: InputEvent) -> void:
	# 鼠标按键事件
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:

				# Ctrl + 左键 → 拆分物品（split half）
				if Input.is_key_pressed(KEY_CTRL):
					_split_item_half()
					return  # 不继续执行拖拽

				# 正常左键 → 开始拖拽
				drag_offset = event.position
				_start_drag({},false)

			else:
				# 松开鼠标左键时结束拖拽
				if is_dragging:
					_end_drag()

	# 鼠标移动事件：拖拽更新
	elif event is InputEventMouseMotion and is_dragging:
		_update_drag()


func _start_drag(from_item: Dictionary, is_split: bool = false) -> void:
	# 如果没有指定物品，则以当前槽的 item_data 为来源
	if from_item == {}:
		if item_data.is_empty():
			return
		drag_source_item = item_data.duplicate(true)  # copy to avoid accidental shared refs
		drag_from_slot_ref = self
		drag_is_split = false
	else:
		# from_item 是拆分产生的新物品
		drag_source_item = from_item.duplicate(true)
		drag_from_slot_ref = self
		drag_is_split = is_split

	is_dragging = true

	# 创建跟随鼠标的预览（显示 drag_source_item）
	drag_preview = Control.new()
	drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_preview.custom_minimum_size = Vector2(32, 32)

	var tex = TextureRect.new()
	tex.texture = ItemDB.get_item(drag_source_item.get("id")).get("icon") if drag_source_item.has("id") else null
	tex.stretch_mode = STRETCH_KEEP_ASPECT_CENTERED
	tex.expand = true
	tex.custom_minimum_size = Vector2(32, 32)
	drag_preview.add_child(tex)

	var label = Label.new()
	label.text = str(drag_source_item.get("count", 0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	drag_preview.z_index = 999
	label.add_theme_color_override("font_color", Color.WHITE)
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	drag_preview.add_child(label)

	# 放到最顶层（挂到 root，保证可见）
	inventory_panel_ref.add_child(drag_preview)
	print("drag is split: ", drag_is_split)
	if not drag_is_split:
		hide_current_icon()
	_update_drag()

func _update_drag() -> void:
	if drag_preview:
		# 让预览中心偏移一点，看起来更自然
		drag_preview.global_position = get_viewport().get_mouse_position() - Vector2(24, 24)
		var mouse_pos = get_viewport().get_mouse_position()
		var current_slot_under_mouse = _get_slot_under_mouse(mouse_pos)
		
		if current_slot_under_mouse:
			if slot_under_mouse and current_slot_under_mouse.name != slot_under_mouse.name:
				slot_under_mouse.hide_forbid()

			slot_under_mouse = current_slot_under_mouse
			if not _check_slot_availability(slot_under_mouse):
				slot_under_mouse.show_forbid()
					
		elif slot_under_mouse:
			slot_under_mouse.hide_forbid()
			
func _check_slot_availability(target_slot) -> bool:
	var source_item = drag_source_item
	var source_item_tag = ItemDB.get_item(source_item["id"])["tag"]
	return source_item_tag in target_slot.accept or "ALL" in target_slot.accept

func show_forbid() -> void:
	$ForbidIcon.visible = true
	
func hide_forbid() -> void:
	$ForbidIcon.visible = false

func _end_drag() -> void:
	if not is_dragging:
		return
	is_dragging = false

	var mouse_pos = get_viewport().get_mouse_position()
	var target_slot = _get_slot_under_mouse(mouse_pos)

	if target_slot and target_slot != drag_from_slot_ref:
		_perform_drop(target_slot)
	else:
		# 放回原位（如果拆分则不需要恢复源，因为源已在拆分时更新）
		_return_item()

	if drag_preview:
		drag_preview.queue_free()
		drag_preview = null

	# 清理拖拽临时数据
	drag_source_item = {}
	drag_from_slot_ref = null
	drag_is_split = false


# ============================================================
# 工具逻辑
# ============================================================
func _get_slot_under_mouse(pos: Vector2) -> Node:
	var slots = get_tree().get_nodes_in_group("cargo_slot")
	for s in slots:
		if s == self:
			continue
		if s.get_global_rect().has_point(pos):
			return s
	return null


func _perform_drop(target_slot: Node) -> void:
	if not target_slot:
		return

	if slot_under_mouse:
		slot_under_mouse.hide_forbid()
		slot_under_mouse = null
	var source_item = drag_source_item
	var source_item_tag = ItemDB.get_item(source_item["id"])["tag"]
	var target_item = target_slot.item_data if target_slot.item_data != null else {}

	#检查item是否能放入
	if source_item_tag in target_slot.accept or "ALL" in target_slot.accept:
		# 目标为空 → 直接放入
		if (target_item == {} or target_item.is_empty()):
			# 如果拖拽物来自拆分（drag_is_split），只需把 source_item 放入目标，
			# 源槽已经在拆分时更新为剩余，不需清空。
			target_slot.set_item(source_item)
			if not drag_is_split:
				# 拖动整个槽（非拆分）时，清空原槽
				set_item({})
			# 底层同步
			if drag_from_slot_ref and drag_from_slot_ref.storage_ref and target_slot.storage_ref:
				target_slot.storage_ref.set_item(target_slot.slot_index, source_item)
				if not drag_is_split:
					drag_from_slot_ref.storage_ref.set_item(drag_from_slot_ref.slot_index, {})
			return

		# 相同 id 且可堆叠 → 叠加逻辑
		var same_id = source_item.has("id") and target_item.has("id") and source_item["id"] == target_item["id"]
		if same_id and source_item.get("stackable", true):
			var max_stack = source_item.get("max_stack", 99)
			var total = source_item.get("count", 1) + target_item.get("count", 1)
			if total <= max_stack:
				# 全部合并到目标
				target_item["count"] = total
				target_slot.set_item(target_item)
				if not drag_is_split:
					set_item({})
				# 底层同步
				if drag_from_slot_ref and drag_from_slot_ref.storage_ref and target_slot.storage_ref:
					target_slot.storage_ref.set_item(target_slot.slot_index, target_item)
					if not drag_is_split:
						drag_from_slot_ref.storage_ref.set_item(drag_from_slot_ref.slot_index, {})
				return
			else:
				# 部分合并，剩余留在拖拽物或源槽
				var overflow = total - max_stack
				target_item["count"] = max_stack
				target_slot.set_item(target_item)
				# 如果拖拽物是拆分出来的，则将 overflow 放回原槽（或作为新堆留在源槽）
				if drag_is_split:
					# 源槽已经被设置为剩余，不处理：但如果 overflow>0，尝试放回源槽或丢弃
					# 这里我们把 overflow 放回源槽（附加到源槽）
					var src_remaining = drag_from_slot_ref.item_data
					if src_remaining == null or src_remaining == {}:
						drag_from_slot_ref.set_item({"id": source_item["id"], "count": overflow})
						if drag_from_slot_ref.storage_ref:
							drag_from_slot_ref.storage_ref.set_item(drag_from_slot_ref.slot_index, drag_from_slot_ref.item_data)
					else:
						# 如果源槽已有，增加其数量（不检查最大堆栈）
						src_remaining["count"] = src_remaining.get("count", 0) + overflow
						drag_from_slot_ref.set_item(src_remaining)
						if drag_from_slot_ref.storage_ref:
							drag_from_slot_ref.storage_ref.set_item(drag_from_slot_ref.slot_index, src_remaining)
				else:
					# 非拆分：源槽留 overflow
					set_item({"id": source_item["id"], "count": overflow})
					if storage_ref:
						storage_ref.set_item(slot_index, {"id": source_item["id"], "count": overflow})
				# 底层同步目标
				if target_slot.storage_ref:
					target_slot.storage_ref.set_item(target_slot.slot_index, target_item)
				return

		# 不同物品 → 交换
		# 把拖拽物放到目标，把目标放回源槽（如果拖拽是拆分，则源槽保持原剩余）
		target_slot.set_item(source_item)
		if not drag_is_split:
			set_item(target_item)
		else:
			# 拆分的情况：源槽已被更新为 remain（不覆盖），但如果你想把目标放回源槽，则做如下：
			drag_from_slot_ref.set_item(target_item)

		# 底层同步
		if target_slot.storage_ref:
			target_slot.storage_ref.set_item(target_slot.slot_index, source_item)
		if drag_from_slot_ref and drag_from_slot_ref.storage_ref:
			# 若拆分则源槽已经被设置过；否则设置为 target_item
			if not drag_is_split:
				drag_from_slot_ref.storage_ref.set_item(drag_from_slot_ref.slot_index, item_data if not drag_is_split else drag_from_slot_ref.item_data)
			else:
				# already handled
				pass
	#不能放入，如果split需返还item
	elif drag_is_split:
		_return_item()
	else:
		show_current_icon()

func hide_current_icon() -> void:
	item_icon.modulate.a = 0.0
	count_label.modulate.a = 0.0


func show_current_icon() -> void:
	item_icon.modulate.a = 1.0
	count_label.modulate.a = 1.0

func _return_item() -> void:
	if drag_is_split:
		item_data["count"] += drag_source_item["count"]
	show_current_icon()
	update_slot_display()

func _split_item_half() -> void:
	if item_data.is_empty():
		return

	var count = int(item_data.get("count", 1))
	if count <= 1:
		return

	var half = count / 2
	var remain = count - half

	# new_item 是要拖拽的那一半
	var new_item = item_data.duplicate(true)
	new_item["count"] = half

	# 源槽保留 remain
	item_data["count"] = remain
	set_item(item_data)
	# 底层同步源槽
	if storage_ref:
		storage_ref.set_item(slot_index, item_data)

	# 启动拖拽（标记为拆分）
	_start_drag(new_item, true)
