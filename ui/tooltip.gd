extends Panel

@export var slot_scene: PackedScene
@onready var textlabel: RichTextLabel = $RichTextLabel
@onready var grid_container: GridContainer = $GridContainer

@export var padding: Vector2 = Vector2(16, 32)

var _last_slot_count: int = -1
var _last_block : Node = null

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
			# ---- 当检测到 Block ----
			visible = true
			global_position = get_viewport().get_mouse_position() + Vector2(16, 16)

			# 读取 slot_count（安全读取）
			var slot_count: int = 0
			var possible = body.get("slot_count")
			if possible != null:
				slot_count = int(possible)
			elif body.has_method("get_slot_count"):
				slot_count = int(body.get_slot_count())
			# else 保持 0

			# 若 slot_count > 0，根据变化才重建
			if slot_count > 0:
				if _last_block != body or _last_slot_count != slot_count:
					_last_block = body
					_last_slot_count = slot_count
					_rebuild_slots(slot_count)
				# 如果已经构建但之前是隐藏状态——确保更新可见性与尺寸
				if not grid_container.visible:
					grid_container.visible = true
					call_deferred("update_panel_size")
			else:
				# 没有槽位：如果之前显示过格子，隐藏并更新尺寸
				if grid_container.visible:
					grid_container.visible = false
					_last_slot_count = -1
					_last_block = null
					call_deferred("update_panel_size")

			# 更新文本（每次 text 改变后也触发尺寸更新）
			var vehicle = null
			if body.has_method("get_parent_vehicle"):
				vehicle = body.get_parent_vehicle() as Vehicle
			if vehicle:
				textlabel.text = body.block_name + "  from  " + vehicle.vehicle_name
			else:
				textlabel.text = body.block_name + ": debris"

			# 文本改变也需要重新布局（延迟）
			call_deferred("update_panel_size")
			return

	# ---- 没检测到 Block（鼠标移开或在别处） ----
	if visible:
		visible = false
	# 当没有 Block 时我们也要重置缓存并更新尺寸（确保 grid 隐藏或缩回）
	_last_block = null
	_last_slot_count = -1
	if grid_container.visible:
		grid_container.visible = false
	call_deferred("update_panel_size")

# 根据 slot_count 重建 GridContainer 的子节点
func _rebuild_slots(slot_count: int) -> void:
	# 清空旧格子
	for child in grid_container.get_children():
		child.queue_free()

	# 让 grid 水平增长（单行）：将列数设置为 slot_count
	# 如果你想固定每行最大列数（例如 6），把下面改为 grid_container.columns = min(slot_count, 6)
	grid_container.columns = min(slot_count, 6)

	# 实例化 slot
	if slot_scene == null:
		printerr("slot_scene is not set in Inspector! Please assign a PackedScene for your slot.")
		return

	for i in range(slot_count):
		var s = slot_scene.instantiate()
		# 如果 slot 需要知道 index / 初始状态，可调用方法或设置属性
		if s.has_method("set_index"):
			s.set_index(i)
		grid_container.add_child(s)

	# 显示 grid 并延迟更新尺寸（保证 Container 布局完成）
	grid_container.visible = true
	call_deferred("update_panel_size")

# 取子控件合并最小尺寸，设置 Panel 的 custom_minimum_size
func update_panel_size() -> void:
	var text_size: Vector2 = textlabel.get_size()
	var grid_size: Vector2 = Vector2.ZERO
	if grid_container.visible:
		grid_size = grid_container.get_size()

	# 宽度取最大的， 高度叠加（label 在上，grid 在下）
	var content_width = max(text_size.x, grid_size.x)
	var content_height = text_size.y
	if grid_container.visible:
		content_height += grid_size.y

	size = Vector2(content_width, content_height) + padding
