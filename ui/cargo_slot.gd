extends TextureRect

@onready var item_icon: TextureRect = $ItemIcon
@onready var count_label: Label = $CountLabel

@export var slot_index: int = 0
@export var storage_ref: Node = null # 指向 Cargo 节点
var item_data: Dictionary = {}       # { "id": "iron", "count": 20, "icon": Texture2D }

var is_dragging := false
var drag_preview = null
var drag_offset := Vector2.ZERO
var drag_origin_pos := Vector2.ZERO


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
	count_label.offset_right = -4
	count_label.offset_bottom = -2
	count_label.add_theme_font_size_override("font_size", 14)
	count_label.visible = false

	add_to_group("cargo_slot")
	call_deferred("update_slot_display")


# ============================================================
# 显示逻辑
# ============================================================
func set_item(item: Dictionary) -> void:
	print("⚡ set_item called on", self)
	print("item:", item)
	item_data = item
	update_slot_display()

func update_slot_display() -> void:
	if item_data.is_empty():
		hide_current_icon()
	else:
		item_icon.texture = item_data.get("icon", null)
		item_icon.visible = true

		var count = item_data.get("count", 1)
		count_label.text = str(count)
		count_label.visible = count > 1


# ============================================================
# 拖放交互
# ============================================================
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				drag_offset = event.position
				_start_drag()
			elif is_dragging:
				_end_drag()
	elif event is InputEventMouseMotion and is_dragging:
		print("updating")
		_update_drag()


func _start_drag() -> void:
	if item_data.is_empty():
		return

	is_dragging = true

	# 创建跟随鼠标的预览
	drag_preview = Control.new()
	drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tex = TextureRect.new()
	tex.texture = item_icon.texture
	tex.stretch_mode = STRETCH_KEEP_ASPECT_CENTERED
	tex.expand = true
	tex.custom_minimum_size = Vector2(32, 32)
	drag_preview.add_child(tex)

	var label = Label.new()
	label.text = count_label.text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.offset_right = -4
	label.offset_bottom = -2
	count_label.add_theme_font_size_override("font_size", 14)
	drag_preview.add_child(label)
	drag_preview.z_index = 999
	
	get_node("/root/Testground/CanvasLayer/Tankpanel").add_child(drag_preview)
	#hide_current_icon()
	#get_tree().root.add_child(drag_preview)
	_update_drag()

func _update_drag() -> void:
	if drag_preview:
		drag_preview.global_position = get_viewport().get_mouse_position() - drag_offset

func _end_drag() -> void:
	is_dragging = false
	var mouse_pos =  get_viewport().get_mouse_position()
	var target_slot = _get_slot_under_mouse(mouse_pos)

	if target_slot and target_slot != self:
		print("dropped")
		_perform_drop(target_slot)
	else:
		print("returned")
		_return_item()

	if drag_preview:
		drag_preview.queue_free()
		drag_preview = null


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
	if not target_slot or target_slot == self:
		return

	var temp_item = target_slot.item_data
	print("temp_item:")
	print(temp_item)
	target_slot.set_item(item_data)
	set_item(temp_item)

	# ✅ 同步底层数据
	if storage_ref and target_slot.storage_ref:
		storage_ref.set_item(slot_index, temp_item)
		target_slot.storage_ref.set_item(target_slot.slot_index, item_data)

	print("✅ Dropped item: ", item_data, " swapped with: ", temp_item)

func hide_current_icon() -> void:
	item_icon.visible = false
	count_label.visible = false

func show_current_icon() -> void:
	item_icon.visible = true
	count_label.visible = true

func _return_item() -> void:
	update_slot_display()
	
