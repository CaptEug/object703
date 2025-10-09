extends TextureRect

@export var slot_index: int
@export var storage_ref: Node  # 指向对应的 small_cargo 节点
var item_data: Dictionary = {} # { "id": "iron", "count": 20, "icon": Texture2D }

func _ready():
	update_slot_display()
	mouse_filter = MOUSE_FILTER_STOP  # 启用鼠标交互

func update_slot_display():
	if item_data.has("icon"):
		texture = item_data["icon"]
	else:
		pass

	if item_data.has("count") and item_data["count"] > 1:
		if not has_node("CountLabel"):
			var lbl = Label.new()
			lbl.name = "CountLabel"
			lbl.anchor_right = 1
			lbl.anchor_bottom = 1
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			add_child(lbl)
		get_node("CountLabel").text = str(item_data["count"])
	elif has_node("CountLabel"):
		get_node("CountLabel").queue_free()

func _gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_on_right_click()

func _on_left_click():
	# 拖动物品
	if item_data:
		print("Picked up item:", item_data)
		storage_ref.pick_item(slot_index)
	else:
		#storage_ref.place_item(slot_index)
		pass

func _on_right_click():
	# 拆分或使用物品
	if item_data:
		print("Right click on", item_data)
		storage_ref.split_item(slot_index)
