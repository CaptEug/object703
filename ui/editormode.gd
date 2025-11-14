extends Control

# === 颜色配置变量 ===
# 虚影块颜色
@export var GHOST_FREE_COLOR = Color(1, 0.3, 0.3, 0.6)  # 不能放置
@export var GHOST_SNAP_COLOR = Color(0.6, 1, 0.6, 0.6)  # 可以放置
@export var GHOST_BLUEPRINT_COLOR = Color(0.3, 0.6, 1.0, 0.6)  # 蓝图虚影颜色
@export var RECYCLE_HIGHLIGHT_COLOR = Color(1, 0.3, 0.3, 0.6)  # 删除模式高亮颜色
@export var BLOCK_DIM_COLOR = Color(0.5, 0.5, 0.5, 0.6)  # 方块变暗颜色

@onready var tab_container = $TabContainer
@onready var description_label = $Panel/RichTextLabel
@onready var build_vehicle_button = $Panel/SaveButton
@onready var save_dialog = $SaveDialog
@onready var name_input = $Panel/NameInput
@onready var error_label = $SaveDialog/ErrorLabel
@onready var recycle_button = $Panel/DismantleButton
@onready var load_button = $Panel/LoadButton
@onready var repair_buttom = $Panel/RepairButton
@onready var mode_button = $Panel/ModeButton

var saw_cursor:Texture = preload("res://assets/icons/saw_cursor.png")

signal block_selected(scene_path: String)
signal vehicle_saved(vehicle_name: String)
signal recycle_mode_toggled(is_recycle_mode: bool)

const GRID_SIZE = 16
const BLOCK_PATHS = {
	"Firepower": "res://blocks/firepower/",
	"Mobility": "res://blocks/mobility/",
	"Command": "res://blocks/command/",
	"Building": "res://blocks/building/",
	"Structual": "res://blocks/structual/",
	"Auxiliary": "res://blocks/auxiliary/"
}

const BLUEPRINT = {
	"BLUEPRINT":"res://vehicles/blueprint/"
}

var item_lists = {}
var is_recycle_mode := false
var is_loading_mode := false
var original_tab_names := []

# === 炮塔编辑模式变量 ===
var is_turret_editing_mode := false
var current_editing_turret: TurretRing = null
var turret_grid_previews := []

# === 炮塔连接点吸附系统 ===
var available_turret_connectors: Array[TurretConnector] = []
var available_block_connectors: Array[TurretConnector] = []
var turret_snap_config: Dictionary = {}

# === 蓝图显示功能 ===
var blueprint_ghosts := []
var blueprint_data: Dictionary
var is_showing_blueprint := false
var ghost_data_map = {}

# === 编辑器模式变量 ===
var is_editing := false
var selected_vehicle: Vehicle = null
var current_ghost_block: Node2D = null
var current_block_scene: PackedScene = null
var panel_instance: Control = null
var camera:Camera2D

# === 模式切换变量 ===
var is_vehicle_mode := true  # true: 车体模式, false: 炮塔模式

# === 方块移动功能变量 ===
var is_moving_block := false
var moving_block: Block = null
var moving_block_original_position: Vector2
var moving_block_original_rotation: float
var moving_block_original_grid_positions: Array
var moving_block_ghost: Node2D = null
var moving_snap_config: Dictionary = {}
var is_mouse_pressed := false
var drag_timer: float = 0.0
var is_dragging := false
var DRAG_DELAY: float = 0.2

# 连接点吸附系统
var current_ghost_connection_index := 0
var current_vehicle_connection_index = 0
var available_ghost_points: Array[Connector] = []
var available_vehicle_points: Array[Connector] = []
var current_snap_config: Dictionary = {}
var snap_config
var is_first_block := true
var is_new_vehicle := false

# 存储原始连接状态
var original_connections: Dictionary = {}
var is_ui_interaction: bool = false

# 虚影数据类
class GhostData:
	var grid_positions: Array
	var rotation_deg: float

func _ready():
	_connect_block_buttons()
	camera = get_tree().current_scene.find_child("Camera2D") as Camera2D
	build_vehicle_button.pressed.connect(_on_build_vehicle_pressed)
	save_dialog.get_ok_button().pressed.connect(_on_save_confirmed)
	save_dialog.close_requested.connect(_on_save_canceled)
	name_input.text_changed.connect(_on_name_input_changed)
	recycle_button.pressed.connect(_on_recycle_button_pressed)
	repair_buttom.pressed.connect(_on_repair_button_pressed)
	mode_button.pressed.connect(_on_mode_button_pressed)
	create_tabs()
	
	save_dialog.hide()
	error_label.hide()
	
	var connect_result = vehicle_saved.connect(_on_vehicle_saved)
	if connect_result == OK:
		print("✅ vehicle_saved Signal connected successfully")
	else:
		print("❌ vehicle_saved 信号连接失败，错误代码:", connect_result)
	
	update_recycle_button()
	load_all_blocks()
	
	call_deferred("initialize_editor")

func _on_mode_button_pressed():
	if not is_editing:
		return
	
	if is_vehicle_mode:
		# 从车体模式切换到炮塔模式
		switch_to_turret_mode()
	else:
		# 从炮塔模式切换回车体模式
		switch_to_vehicle_mode()

func switch_to_turret_mode():
	"""切换到炮塔模式并自动进入第一个炮塔的编辑模式"""
	if not is_editing or not selected_vehicle:
		return
	
	print("=== 切换到炮塔模式 ===")
	
	# 退出当前所有特殊模式
	if is_recycle_mode:
		exit_recycle_mode()
	
	if current_ghost_block:
		current_ghost_block.queue_free()
		current_ghost_block = null
	
	# 切换到炮塔模式
	is_vehicle_mode = false
	print("is_vehicle_mode 设置为: ", is_vehicle_mode)
	
	# 重要：查找并进入第一个炮塔的编辑模式
	var turrets = get_turret_blocks()
	if turrets.is_empty():
		print("❌ 车辆上没有找到炮塔，无法进入炮塔编辑模式")
		# 如果没有炮塔，切换回车体模式
		is_vehicle_mode = true
		update_mode_button_display()
		return
	
	# 进入第一个炮塔的编辑模式
	var first_turret = turrets[0]
	print("🎯 找到炮塔，进入编辑模式:", first_turret.block_name)
	enter_turret_editing_mode(first_turret)
	
	print("切换到炮塔编辑模式完成")

func switch_to_vehicle_mode():
	"""切换回车体模式"""
	if not is_editing:
		return
	
	print("=== 切换回车体模式 ===")
	
	# 如果正在炮塔编辑模式，退出
	if is_turret_editing_mode:
		exit_turret_editing_mode()
	
	# 切换到车体模式
	is_vehicle_mode = true
	print("is_vehicle_mode 设置为: ", is_vehicle_mode)
	
	# 重要：更新按钮显示
	update_mode_button_display()
	
	print("切换回车体模式完成")

func update_mode_button_display():
	"""更新模式按钮的显示"""
	if not mode_button:
		return
	
	if is_vehicle_mode:
		# 车体模式：显示车体图标
		mode_button.tooltip_text = "车体编辑模式 (点击切换到炮塔编辑)"
	else:
		# 炮塔模式：显示炮塔图标
		mode_button.tooltip_text = "炮塔编辑模式 (点击切换回车体编辑)"

func _connect_block_buttons():
	var block_buttons = get_tree().get_nodes_in_group("block_buttons")
	for button in block_buttons:
		if button is BaseButton:
			button.pressed.connect(_on_block_button_pressed)

func _on_block_button_pressed():
	is_ui_interaction = true
	await get_tree().create_timer(0.2).timeout
	is_ui_interaction = false

func _input(event):
	# B键切换编辑模式
	if event is InputEventKey and event.pressed and event.keycode == KEY_B:
		if is_editing:
			exit_editor_mode()
		else:
			if selected_vehicle == null:
				find_and_select_vehicle()
			if selected_vehicle:
				enter_editor_mode(selected_vehicle)
			else:
				print("错误: 未找到可编辑的车辆")
		return
	
	# ESC键取消操作
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if is_turret_editing_mode:
			exit_turret_editing_mode()
			return
		cancel_placement()
	
	# 其他快捷键处理
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				if current_ghost_block:
					rotate_ghost_connection()
			KEY_X:
				# 切换删除模式
				if is_recycle_mode:
					exit_recycle_mode()
				else:
					enter_recycle_mode()
			KEY_T:
				# 切换蓝图显示
				if is_editing and selected_vehicle:
					toggle_blueprint_display()
			KEY_N:
				# 新建车辆
				if not is_editing:
					create_new_vehicle()
			KEY_L:
				# 切换加载模式
				if is_loading_mode:
					switch_to_normal_mode()
				else:
					switch_to_loading_mode()
			KEY_F:
				# 修复车辆
				if is_editing and selected_vehicle and is_showing_blueprint:
					repair_blueprint_missing_blocks()

	# 鼠标按键处理
	if event is InputEventMouseButton:
		if get_viewport().gui_get_hovered_control():
			return
		if event.pressed:
			# 鼠标按下事件
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					# 鼠标左键按下
					is_mouse_pressed = true
					drag_timer = 0.0
					is_dragging = false
					
					if is_turret_editing_mode:
						# 炮塔编辑模式下的点击处理
						var mouse_pos = get_viewport().get_mouse_position()
						var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
						
						# 检查是否点击到其他炮塔
						var clicked_turret = get_turret_at_position(global_mouse_pos)
						var clicked_self = false
						
						# 检查是否点击到自己（当前编辑的炮塔）
						if current_editing_turret == clicked_turret:
							clicked_self = true
						
						if current_ghost_block:
							# 有幽灵方块时的放置逻辑
							var can_place = turret_snap_config and not turret_snap_config.is_empty()
							
							if can_place and not is_recycle_mode:
								try_place_turret_block()
							elif is_recycle_mode:
								try_remove_turret_block()
							else:
								# 不能放置且不在删除模式，保持当前状态不退出
								pass
						else:
							# 没有幽灵方块时的点击逻辑
							if is_recycle_mode:
								try_remove_turret_block()
							if clicked_turret and clicked_turret != current_editing_turret:
								# 点击到其他炮塔，切换到该炮塔的编辑模式
								exit_turret_editing_mode()
								enter_turret_editing_mode(clicked_turret)
					
					elif is_editing and not is_turret_editing_mode and not is_recycle_mode and not is_moving_block:
						# 进入炮塔编辑模式
						var mouse_pos = get_viewport().get_mouse_position()
						var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
						var clicked_turret = get_turret_at_position(global_mouse_pos)
						
						if clicked_turret:
							enter_turret_editing_mode(clicked_turret)
							return
					
					# 其他左键按下逻辑（非炮塔编辑模式）
					if not is_turret_editing_mode:
						if is_recycle_mode:
							if is_turret_editing_mode:
								# 炮塔编辑模式下的删除
								try_remove_turret_block()
							else:
								# 普通删除模式
								try_remove_block()
							
						if not is_recycle_mode and not current_ghost_block and not is_turret_editing_mode:
							var mouse_pos = get_viewport().get_mouse_position()
							var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
							var block = get_block_at_position(global_mouse_pos)
							if block:
								print("检测到方块，开始拖拽计时")
				
				MOUSE_BUTTON_RIGHT:
					# 右键取消操作
					if is_recycle_mode:
						exit_recycle_mode()
					elif is_turret_editing_mode and current_ghost_block == null:
						exit_turret_editing_mode()
					else:
						cancel_placement()
						
				
				MOUSE_BUTTON_MIDDLE:
					# 右键取消操作
					if is_recycle_mode:
						exit_recycle_mode()
					elif is_turret_editing_mode and current_ghost_block == null:
						exit_turret_editing_mode()
					else:
						cancel_placement()
						
		else:
			# 鼠标释放事件
			if event.button_index == MOUSE_BUTTON_LEFT:
				# 鼠标左键释放
				is_mouse_pressed = false
				try_place_block()

func _process(delta):
	if is_editing and selected_vehicle:
		camera.sync_rotation_to_vehicle(selected_vehicle)
	
	if is_showing_blueprint and not blueprint_ghosts.is_empty():
		update_ghosts_transform()	
	
	if is_editing and is_recycle_mode and selected_vehicle:
		update_recycle_highlight()
		
	if not is_editing or not selected_vehicle:
		return
	
	# 更新炮塔边框位置
	if is_turret_editing_mode and not turret_selection_borders.is_empty():
		update_turret_border_positions()
	
	if current_ghost_block and Engine.get_frames_drawn() % 2 == 0:
		var mouse_pos = get_viewport().get_mouse_position()
		var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
		if is_turret_editing_mode:
			update_turret_placement_feedback()
		else:
			update_ghost_block_position(global_mouse_pos)
	
	if is_turret_editing_mode and current_ghost_block:
		update_turret_placement_feedback()

# === 炮塔编辑模式功能 ===
func enter_turret_editing_mode(turret: TurretRing):
	if is_turret_editing_mode:
		exit_turret_editing_mode()
	
	print("=== 进入炮塔编辑模式 ===")
	print("   目标炮塔:", turret.block_name if turret else "null")
	mode_button.button_pressed = true
	is_turret_editing_mode = true
	current_editing_turret = turret
	cancel_placement()
	for point in turret.turret_basket.get_children():
		if point is TurretConnector:
			if point.connected_to == null:
				point.is_connection_enabled = true
	# 重要：确保在炮塔模式下
	if is_vehicle_mode:
		is_vehicle_mode = false
		print("🔄 自动切换到炮塔模式")
	
	# 更新按钮显示
	update_mode_button_display()
	
	reset_turret_rotation(turret)
	disable_turret_rotation(turret)
	
	# 设置块的颜色状态：只有当前编辑炮塔高亮，其他所有块变暗
	reset_all_blocks_color()
	
	if current_ghost_block:
		current_ghost_block.visible = false
	
	if is_recycle_mode:
		# 保持删除模式，但更新光标和功能
		Input.set_custom_mouse_cursor(saw_cursor)
		print("炮塔编辑模式：删除功能已切换到炮塔专用")
	
	clear_tab_container_selection()
	
	print("炮塔编辑模式进入完成，当前模式:", "车体" if is_vehicle_mode else "炮塔")

func exit_turret_editing_mode():
	if not is_turret_editing_mode:
		return
	
	print("=== 退出炮塔编辑模式 ===")
	
	is_turret_editing_mode = false
	mode_button.button_pressed = false
	# 清除所有炮塔边框
	clear_all_turret_borders()
	
	if current_editing_turret:
		enable_turret_rotation(current_editing_turret)
	
	Input.set_custom_mouse_cursor(null)
	
	# 恢复所有块的颜色
	if selected_vehicle:
		for block in selected_vehicle.blocks:
			if is_instance_valid(block):
				block.modulate = Color.WHITE
	
	if is_recycle_mode:
		Input.set_custom_mouse_cursor(saw_cursor)
	
	turret_snap_config = {}
	available_turret_connectors.clear()
	available_block_connectors.clear()
	
	if current_ghost_block:
		current_ghost_block.visible = true
	
	if not is_vehicle_mode:
		is_vehicle_mode = true
	
	# 重要：退出炮塔编辑模式时，根据当前模式更新按钮显示
	update_mode_button_display()
	
	current_editing_turret = null
	
	print("炮塔编辑模式退出完成")

func reset_turret_rotation(turret: TurretRing):
	if turret and is_instance_valid(turret):
		turret.reset_turret_rotation()

func disable_turret_rotation(turret: TurretRing):
	if turret and is_instance_valid(turret):
		turret.lock_turret_rotation()

func enable_turret_rotation(turret: TurretRing):
	if turret and is_instance_valid(turret):
		turret.unlock_turret_rotation()

func dim_non_turret_blocks(dim: bool):
	if not selected_vehicle:
		return
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			# 当前编辑的炮塔保持高亮，不受变暗影响
			if block == current_editing_turret:
				continue
			
			if dim:
				block.modulate = BLOCK_DIM_COLOR
			else:
				block.modulate = Color.WHITE

# === 炮塔编辑模式吸附系统 ===
func update_turret_placement_feedback():
	"""炮塔编辑模式吸附反馈"""
	if not is_turret_editing_mode or not current_ghost_block or not current_editing_turret:
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	update_turret_editing_snap_system(global_mouse_pos)

func update_turret_editing_snap_system(mouse_position: Vector2):
	"""炮塔编辑模式吸附系统 - 根据范围决定连接方式"""
	if not is_turret_editing_mode or not current_ghost_block or not current_editing_turret:
		set_ghost_free_position(mouse_position)
		return
	
	# 根据位置决定连接方式
	var in_range = is_position_in_turret_range_for_ghost(mouse_position)
	
	if in_range:
		update_turret_range_placement(mouse_position)  # 阶段1：炮塔范围内
	else:
		update_outside_turret_placement(mouse_position)  # 阶段2：炮塔范围外

func is_position_in_turret_range_for_ghost(mouse_position: Vector2) -> bool:
	"""检测虚影块是否可以放在炮塔范围内"""
	if not current_editing_turret or not current_ghost_block:
		return false
	
	# 获取炮塔的网格范围
	var _turret_bounds = current_editing_turret.get_turret_grid_bounds()
	var turret_use = current_editing_turret.turret_basket
	
	# 计算鼠标在炮塔局部坐标系中的位置
	var local_mouse_pos = turret_use.to_local(mouse_position)
	
	# 先检查鼠标位置是否在炮塔的物理范围内（考虑炮塔尺寸）
	var turret_width = current_editing_turret.size.x * GRID_SIZE
	var turret_height = current_editing_turret.size.y * GRID_SIZE
	var turret_half_width = turret_width / 2.0
	var turret_half_height = turret_height / 2.0
	
	# 检查鼠标是否在炮塔矩形范围内
	var is_in_turret_area = (
		local_mouse_pos.x >= -turret_half_width and 
		local_mouse_pos.x <= turret_half_width and 
		local_mouse_pos.y >= -turret_half_height and 
		local_mouse_pos.y <= turret_half_height
	)
	
	if not is_in_turret_area:
		return false
	
	# 将局部位置转换为网格坐标（以炮塔中心为原点）
	var grid_x = int(floor(local_mouse_pos.x / GRID_SIZE))
	var grid_y = int(floor(local_mouse_pos.y / GRID_SIZE))
	
	# 调整网格坐标到炮塔的网格坐标系
	var adjusted_grid_x = grid_x
	var adjusted_grid_y = grid_y
	
	# 计算虚影块的所有网格位置（考虑旋转）
	var ghost_grid_positions = calculate_ghost_grid_positions_for_turret(
		Vector2i(adjusted_grid_x, adjusted_grid_y), 
		current_ghost_block.base_rotation_degree
	)
	
	# 检查所有网格位置是否都在炮塔范围内且可用
	for pos in ghost_grid_positions:
		if not current_editing_turret.is_position_available(pos):
			return false
	
	return true

func calculate_ghost_grid_positions_for_turret(base_pos: Vector2i, rotation_deg: float) -> Array:
	"""计算虚影块在炮塔局部坐标系中的所有网格位置"""
	var grid_positions = []
	var block_size = current_ghost_block.size
	
	for x in range(block_size.x):
		for y in range(block_size.y):
			var grid_pos: Vector2i
			
			match int(rotation_deg):
				0:
					grid_pos = base_pos + Vector2i(x, y)
				90:
					grid_pos = base_pos + Vector2i(-y, x)
				-90, 270:
					grid_pos = base_pos + Vector2i(y, -x)
				180, -180:
					grid_pos = base_pos + Vector2i(-x, -y)
				_:
					grid_pos = base_pos + Vector2i(x, y)
			
			grid_positions.append(grid_pos)
	
	return grid_positions

func update_turret_range_placement(mouse_position: Vector2):
	"""在炮塔范围内：使用RigidBody连接到炮塔平台"""
	var available_turret_points = get_turret_platform_connectors()
	var available_ghost_points_ = get_ghost_block_rigidbody_connectors()
	
	if available_turret_points.is_empty() or available_ghost_points_.is_empty():
		set_ghost_free_position(mouse_position)
		return
	
	var best_snap = find_best_rigidbody_snap_config(mouse_position, available_turret_points, available_ghost_points_)
	
	if best_snap and not best_snap.is_empty():
		apply_turret_snap_config(best_snap)
	else:
		set_ghost_free_position(mouse_position)

func update_outside_turret_placement(mouse_position: Vector2):
	"""在炮塔范围外：使用Connector连接到炮塔上已有的块"""
	var available_block_points = get_turret_block_connection_points()
	var available_ghost_points_ = get_ghost_block_connection_points()
	
	if available_block_points.is_empty() or available_ghost_points_.is_empty():
		set_ghost_free_position(mouse_position)
		return
	
	var best_snap = find_best_regular_snap_config_for_turret(mouse_position, available_block_points, available_ghost_points_)
	
	if best_snap and not best_snap.is_empty():
		apply_turret_snap_config(best_snap)
	else:
		set_ghost_free_position(mouse_position)

func get_turret_connection_point_global_position(point: Connector, block: Block) -> Vector2:
	"""获取炮塔上块的连接点的全局位置"""
	# 炮塔上的块应该使用块的全局位置，而不是炮塔座圈的位置
	return block.global_position + point.position.rotated(block.global_rotation)

func try_remove_turret_block():
	"""炮塔编辑模式下删除块 - 只删除炮塔上的块"""
	print("=== 尝试从炮塔移除block ===")
	
	if not is_turret_editing_mode:
		print("❌ 不在炮塔编辑模式")
		return
		
	if not current_editing_turret:
		print("❌ 没有当前编辑的炮塔")
		return
		
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	print("鼠标位置 - 屏幕:", mouse_pos, " 世界:", global_mouse_pos)
	
	# 在炮塔范围内检测要删除的块
	var block_to_remove = get_turret_block_at_position(global_mouse_pos)
	
	print("找到的块:", block_to_remove)
	
	if block_to_remove and block_to_remove != current_editing_turret:
		print("✅ 准备移除块:", block_to_remove.block_name)
		current_editing_turret.remove_block_from_turret(block_to_remove)
		print("✅ 块移除完成")
	else:
		if not block_to_remove:
			print("❌ 没有找到要删除的块")
		elif block_to_remove == current_editing_turret:
			print("⚠️ 不能删除炮塔座圈本身")

func get_turret_block_at_position(position: Vector2) -> Block:
	"""获取炮塔上指定位置的块（排除炮塔座圈本身）"""
	
	var space_state = get_tree().root.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = position
	query.collision_mask = 2  # 使用炮塔编辑模式的碰撞层
	
	var result = space_state.intersect_point(query)
	
	for collision in result:
		var block = collision.collider
		
		if (block is Block and 
			block != current_editing_turret and 
			is_block_on_turret(block)):
			return block
			
	return null

func is_block_on_turret(block: Block) -> bool:
	"""检查块是否属于当前编辑的炮塔"""
	if not current_editing_turret:
		return false
	
	# 检查块是否直接附加到炮塔上
	var attached_blocks = current_editing_turret.get_attached_blocks()
	return block in attached_blocks

func remove_turret_block(block: Block):
	"""从炮塔上移除块"""
	if not block or not current_editing_turret:
		return
	
	print("正在从炮塔移除块: ", block.block_name)
	
	# 断开所有连接
	var connections_to_disconnect = find_connections_for_block(block)
	disconnect_connections(connections_to_disconnect)
	
	# 从炮塔上移除块
	current_editing_turret.remove_block_from_turret(block)
	
	# 从车辆中完全移除
	if selected_vehicle:
		var control = selected_vehicle.control
		selected_vehicle.remove_block(block, true)
		selected_vehicle.control = control
	
	# 更新炮塔显示
	if selected_vehicle:
		selected_vehicle.update_vehicle()
	
	print("炮塔块移除完成")

func find_best_regular_snap_config_for_turret(mouse_position: Vector2, block_points: Array[Connector], ghost_points: Array[Connector]) -> Dictionary:
	"""用于炮塔普通Connector连接的吸附配置 - 修复版"""
	var best_config = {}
	var min_distance = INF
	var SNAP_DISTANCE = 16.0
	for block_point in block_points:
		var block = block_point.find_parent_block()
		if not block:
			continue
		
		# 再次确保不是炮塔座圈
		if block == current_editing_turret:
			print("跳过炮塔座圈本身的连接点")
			continue
			
		var block_point_global = get_turret_connection_point_global_position(block_point, block)
		
		for ghost_point in ghost_points:
			# 计算目标旋转
			var target_rotation = calculate_aligned_rotation_for_turret_block(block)
			
			if not can_points_connect_with_rotation_for_turret(block_point, ghost_point, target_rotation):
				continue
				
			# 计算网格位置
			var positions = calculate_rotated_grid_positions_for_turret(block_point, ghost_point)
			if positions is bool or positions.is_empty():
				continue
				
			# 计算虚影位置
			var ghost_local_offset = ghost_point.position.rotated(target_rotation)
			var ghost_position = block_point_global - ghost_local_offset
			
			var distance = mouse_position.distance_to(ghost_position)
			
			if distance < SNAP_DISTANCE and distance < min_distance:
				min_distance = distance
				best_config = {
					"vehicle_point": block_point,
					"ghost_point": ghost_point,
					"ghost_position": ghost_position,
					"ghost_rotation": target_rotation,
					"vehicle_block": block,
					"positions": positions,
					"grid_positions": positions
				}
		
	return best_config

func calculate_aligned_rotation_for_turret_block(vehicle_block: Block) -> float:
	"""计算炮塔块的对齐旋转 - 修正版"""
	# 使用车辆块的全局旋转，加上虚影的基础旋转
	# 减去相机旋转以确保基础旋转正确
	var world_rotation = vehicle_block.global_rotation
	var self_rotation = deg_to_rad(vehicle_block.base_rotation_degree)
	var base_rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	
	return world_rotation + base_rotation - self_rotation

func can_points_connect_with_rotation_for_turret(point_a: Connector, point_b: Connector, ghost_rotation: float) -> bool:
	"""检查炮塔连接点是否可以连接 - 修复版"""
	if point_a.connection_type != point_b.connection_type:
		return false
	if not point_a.is_connection_enabled or not point_b.is_connection_enabled:
		return false
	
	# 计算虚影连接点的全局方向
	var ghost_point_direction = point_b.rotation + ghost_rotation
	var vehicle_point_direction = point_a.global_rotation
	
	# 检查方向是否相对
	var can_connect = are_rotations_opposite_best(ghost_point_direction, vehicle_point_direction)
	return can_connect

func calculate_rotated_grid_positions_for_turret(turret_point: Connector, ghost_point: Connector):
	"""计算旋转后的网格位置 - 用于连接吸附"""
	var grid_positions = []
	var grid_block = {}
	
	if not current_editing_turret:
		return grid_positions
	
	var block_size = ghost_point.find_parent_block().size

	var location_v = turret_point.location
	
	var rotation_b = turret_point.find_parent_block().base_rotation_degree
	var grid_b = {}
	var grid_b_pos = {}
	
	# 获取车辆块的网格位置
	for key in current_editing_turret.turret_grid:
		if current_editing_turret.turret_grid[key] == turret_point.find_parent_block():
			grid_b[key] = current_editing_turret.turret_grid[key]
	
	grid_b_pos = get_rectangle_corners(grid_b)
	var grid_connect_g
	if grid_b_pos.is_empty():
		return false
	var connect_pos_v
	if rotation_b == 0:
		connect_pos_v = Vector2i(grid_b_pos["1"].x + location_v.x, grid_b_pos["1"].y + location_v.y)
	elif rotation_b == -90:
		connect_pos_v = Vector2i(grid_b_pos["4"].x + location_v.y, grid_b_pos["4"].y - location_v.x)
	elif rotation_b == -180 or rotation_b == 180:
		connect_pos_v = Vector2i(grid_b_pos["3"].x - location_v.x, grid_b_pos["3"].y - location_v.y)
	elif rotation_b == 90:
		connect_pos_v = Vector2i(grid_b_pos["2"].x - location_v.y, grid_b_pos["2"].y + location_v.x)
	grid_connect_g = get_connection_offset(connect_pos_v, turret_point.rotation, turret_point.find_parent_block().base_rotation_degree)
	
	if grid_connect_g != null and block_size != null and ghost_point.location != null:
		grid_block = to_grid(grid_connect_g, block_size, ghost_point.location)
	
	for pos in grid_block:
		if current_editing_turret.turret_grid.has(pos):
			return false
		grid_positions.append(pos)
	
	return grid_positions

func calculate_base_grid_position_for_turret(vehicle_loc: Vector2i, ghost_loc: Vector2i, _rotation_: float) -> Vector2i:
	"""计算基础网格位置 - 简化版"""
	# 简化计算：直接使用连接点位置
	var base_x = vehicle_loc.x - ghost_loc.x
	var base_y = vehicle_loc.y - ghost_loc.y
	
	return Vector2i(base_x, base_y)

func calculate_all_grid_positions_for_turret_simple(base_pos: Vector2i, block_size: Vector2i, rotation_deg: float) -> Array:
	"""计算炮塔块的所有网格位置 - 简化版"""
	var positions = []
	
	for x in range(block_size.x):
		for y in range(block_size.y):
			var grid_pos: Vector2i
			
			match int(rotation_deg):
				0:
					grid_pos = base_pos + Vector2i(x, y)
				90:
					grid_pos = base_pos + Vector2i(-y, x)
				-90, 270:
					grid_pos = base_pos + Vector2i(y, -x)
				180, -180:
					grid_pos = base_pos + Vector2i(-x, -y)
				_:
					grid_pos = base_pos + Vector2i(x, y)
			
			positions.append(grid_pos)
	
	return positions

func are_turret_grid_positions_available_for_placement(grid_positions: Array) -> bool:
	"""检查炮塔网格位置是否可用于放置"""
	for pos in grid_positions:
		if selected_vehicle.grid.has(pos):
			return false
	return true

func get_turret_platform_connectors() -> Array[TurretConnector]:
	"""获取炮塔平台本身的TurretConnector"""
	var points: Array[TurretConnector] = []
	
	if not current_editing_turret:
		return points
	
	var connectors = current_editing_turret.find_children("*", "TurretConnector", true)
	for connector in connectors:
		if (connector is TurretConnector and 
			connector.is_connection_enabled and 
			connector.connected_to == null):
			points.append(connector)
	
	return points

func get_turret_block_connection_points() -> Array[Connector]:
	"""获取炮塔上其他块的Connector - 排除炮塔座圈本身"""
	var points: Array[Connector] = []
	
	if not current_editing_turret:
		return points
	
	# 获取炮塔上所有已附加的块
	var attached_blocks = current_editing_turret.get_attached_blocks()
	
	for block in attached_blocks:
		if is_instance_valid(block):
			# 明确排除炮塔座圈本身
			if block == current_editing_turret:
				print("跳过炮塔座圈本身")
				continue
				
			
			# 获取该块的所有可用连接点
			var available_points = 0
			for point in block.connection_points:
				if (point is Connector and 
					point.is_connection_enabled and 
					point.connected_to == null):
					points.append(point)
					available_points += 1
	return points
	
func get_ghost_block_rigidbody_connectors() -> Array[TurretConnector]:
	"""获取虚影块的TurretConnector"""
	var points: Array[TurretConnector] = []
	
	if not current_ghost_block:
		return points
	
	var connectors = current_ghost_block.find_children("*", "TurretConnector", true)
	for connector in connectors:
		if (connector is TurretConnector and 
			connector.is_connection_enabled and 
			connector.connected_to == null):
			points.append(connector)
	
	return points

func get_ghost_block_connection_points() -> Array[Connector]:
	"""获取虚影块的Connector"""
	var points: Array[Connector] = []
	if current_ghost_block:
		var connection_points = current_ghost_block.get_available_connection_points()
		for point in connection_points:
			if point is Connector:
				point.qeck = false
				points.append(point)
	return points

func find_best_rigidbody_snap_config(mouse_position: Vector2, turret_points: Array[TurretConnector], ghost_points: Array[TurretConnector]) -> Dictionary:
	"""专门用于RigidBody连接的吸附配置 - 修复键名"""
	var best_config = {}
	var min_distance = INF
	
	for turret_point in turret_points:
		for ghost_point in ghost_points:
			if not can_rigidbody_connectors_connect(turret_point, ghost_point):
				continue
			
			var snap_config = calculate_rigidbody_snap_config(turret_point, ghost_point)
			if snap_config.is_empty():
				continue
			
			# 修复：使用 ghost_position 而不是 world_position
			var target_position = snap_config.get("ghost_position", Vector2.ZERO)
			var distance = mouse_position.distance_to(target_position)
			
			if distance < turret_point.snap_distance_threshold and distance < min_distance:
				min_distance = distance
				best_config = snap_config  # 这里直接使用完整的 snap_config，它应该包含 grid_positions
	
	return best_config

func find_best_regular_snap_config(mouse_position: Vector2, block_points: Array[Connector], ghost_points: Array[Connector]) -> Dictionary:
	"""用于普通Connector连接的吸附配置"""
	var best_config = {}
	var min_distance = INF
	
	for block_point in block_points:
		var block = block_point.find_parent_block()
		if not block:
			continue
			
		var block_point_global = get_connection_point_global_position(block_point, block)
		
		for ghost_point in ghost_points:
			var target_rotation = calculate_aligned_rotation_from_base(block)
			if not can_points_connect_with_rotation(block_point, ghost_point, target_rotation):
				continue
		
			var positions = calculate_rotated_grid_positions(block_point, ghost_point)
			if positions is bool:
				continue
				
			var ghost_local_offset = ghost_point.position.rotated(target_rotation)
			var ghost_position = block_point_global - ghost_local_offset
			
			var distance = mouse_position.distance_to(ghost_position)
			if distance < min_distance:
				min_distance = distance
				best_config = {
					"vehicle_point": block_point,
					"ghost_point": ghost_point,
					"ghost_position": ghost_position,
					"ghost_rotation": target_rotation,
					"vehicle_block": block,
					"positions": positions
				}
	
	return best_config

func calculate_rigidbody_snap_config(turret_point: TurretConnector, ghost_point: TurretConnector) -> Dictionary:
	"""计算RigidBody连接的吸附配置 - 完整版"""
	if not turret_point or not ghost_point:
		return {}
	
	if not current_ghost_block:
		return {}
	
	if not current_editing_turret:
		return {}
	
	# 获取炮塔连接点的世界位置和网格位置
	var turret_world_pos = turret_point.global_position
	var turret_grid_pos = Vector2i(turret_point.location.x, turret_point.location.y)
	
	# 获取虚影连接点的局部位置和网格位置
	var ghost_local_pos = ghost_point.position
	var ghost_grid_pos = Vector2i(ghost_point.location.x, ghost_point.location.y)
	
	# 计算目标旋转（基于连接点方向）
	var target_rotation = calculate_turret_block_rotation(turret_point, ghost_point)
	
	# 计算基础网格位置
	var base_grid_pos = turret_point.location
	
	# 计算所有网格位置
	var grid_positions = calculate_all_grid_positions(base_grid_pos, current_ghost_block.size, ghost_point)
	
	# 检查位置是否可用
	if not are_turret_grid_positions_available(grid_positions, current_editing_turret):
		return {}
	
	# 计算世界位置
	var world_position = calculate_turret_world_position(turret_point, ghost_local_pos, deg_to_rad(ghost_point.get_parent().base_rotation_degree))
	
	var snap_config = {
		"turret_point": turret_point,
		"ghost_point": ghost_point,
		"ghost_position": world_position,  # 统一使用ghost_position键名
		"ghost_rotation": target_rotation, # 统一使用ghost_rotation键名
		"rotation": target_rotation,       # 保持向后兼容
		"grid_positions": grid_positions,  # 确保包含网格位置
		"positions": grid_positions,       # 添加positions键用于兼容性
		"base_grid_pos": base_grid_pos,
		"connection_type": "rigidbody"
	}
	
	return snap_config

func calculate_all_grid_positions(base_pos: Vector2i, block_size: Vector2i, ghost_point: TurretConnector) -> Array:
	"""计算块的所有网格位置"""
	var positions = []
	var local_pos = ghost_point.location
	var zero_pos = Vector2i.ZERO
	match int(ghost_point.get_parent().base_rotation_degree):
		0:
			zero_pos = base_pos - local_pos
		90:
			zero_pos = base_pos + Vector2i(local_pos.y, -local_pos.x)
		-90, 270:
			zero_pos = base_pos + Vector2i(-local_pos.y, local_pos.x)
		180, -180:
			zero_pos = base_pos + Vector2i(local_pos.x, local_pos.y)
		_:
			zero_pos = base_pos - local_pos
	for i in block_size.x:
		for j in block_size.y:
			var one_point
			match int(ghost_point.get_parent().base_rotation_degree):
				0:
					one_point = Vector2i(zero_pos.x + i, zero_pos.y + j)
				90:
					one_point = Vector2i(zero_pos.x - j, zero_pos.y + i)
				-90, 270:
					one_point = Vector2i(zero_pos.x + j, zero_pos.y - i)
				180, -180:
					one_point = Vector2i(zero_pos.x - i, zero_pos.y - j)
			positions.append(one_point)
	return positions

func calculate_single_grid_position(base_pos: Vector2i, local_pos: Vector2i, block_size: Vector2i, rotation: float) -> Vector2i:
	"""计算单个网格位置"""
	var rotation_deg = rad_to_deg(rotation)
	
	match int(rotation_deg):
		0:
			return base_pos + local_pos
		90:
			return base_pos + Vector2i(-local_pos.y, local_pos.x)
		-90, 270:
			return base_pos + Vector2i(local_pos.y, -local_pos.x)
		180:
			return base_pos + Vector2i(-local_pos.x, -local_pos.y)
		_:
			return base_pos + local_pos

func calculate_turret_world_position(turret_point: TurretConnector, ghost_local_pos: Vector2, rotation: float) -> Vector2:
	"""计算炮塔块的世界位置"""
	# 世界位置 = 炮塔连接点位置 - 旋转后的虚影连接点局部位置
	var use_pos = turret_point.position - ghost_local_pos.rotated(rotation)
	return turret_point.get_parent().to_global(use_pos)

func calculate_turret_block_rotation(turret_point: TurretConnector, ghost_point: TurretConnector) -> float:
	"""计算炮塔块旋转 - 简化和稳定版本"""
	# 获取炮塔连接器的方向
	var turret_direction = turret_point.global_rotation
	
	# 获取虚影连接器的方向（考虑基础旋转）
	var ghost_base_rotation = deg_to_rad(ghost_point.get_parent().base_rotation_degree)
	var ghost_direction = ghost_base_rotation
	
	var relative_rotation = turret_direction + ghost_direction
	
	return relative_rotation

func rotate_grid_offset(offset: Vector2i, rotation_use: float) -> Vector2i:
	"""旋转网格偏移"""
	var rotation_deg = rotation_use
	
	match int(rotation_deg):
		0:
			return offset
		90:
			return Vector2i(-offset.y, offset.x)
		-90, 270:
			return Vector2i(offset.y, -offset.x)
		180:
			return Vector2i(-offset.x, -offset.y)
		_:
			return offset

func can_rigidbody_connectors_connect(connector_a: TurretConnector, connector_b: TurretConnector) -> bool:
	"""检查RigidBody连接点是否可以连接"""
	if not connector_a or not connector_b:
		return false
	
	if connector_a.connection_type != connector_b.connection_type:
		return false
	
	if not connector_a.is_connection_enabled or not connector_b.is_connection_enabled:
		return false
	
	if connector_a.connected_to != null or connector_b.connected_to != null:
		return false
	
	# 确保一个是炮塔平台，一个是块
	var a_is_turret = connector_a.get_parent() is Block
	var b_is_turret = connector_b.get_parent() is Block
	
	return a_is_turret != b_is_turret

func are_turret_grid_positions_available(grid_positions: Array, turret: TurretRing) -> bool:
	"""检查网格位置是否可用"""
	for pos in grid_positions:
		if pos:
			if not turret.is_position_available(pos):
				return false
		#else:
			#print(grid_positions)
	return true

func apply_turret_snap_config(snap_config: Dictionary):
	"""应用炮塔吸附配置到虚影 - 修复版"""
	# 检查字典中是否包含必要的键
	if not snap_config.has("ghost_position"):
		print("❌ 吸附配置缺少 ghost_position")
		return
	
	current_ghost_block.global_position = snap_config.ghost_position
	
	if snap_config.has("ghost_rotation"):
		current_ghost_block.global_rotation = snap_config.ghost_rotation
	else:
		# 如果没有提供旋转，使用基础旋转加上相机旋转
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
	
	current_ghost_block.modulate = GHOST_SNAP_COLOR
	
	# 存储吸附配置用于放置
	turret_snap_config = snap_config.duplicate()  # 使用副本避免引用问题

func set_ghost_free_position(mouse_position: Vector2):
	"""设置虚影自由位置（无吸附）"""
	current_ghost_block.global_position = mouse_position
	current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
	current_ghost_block.modulate = GHOST_FREE_COLOR  # 红色：不能放置
	turret_snap_config = {}

func try_place_turret_block():
	"""炮塔编辑模式放置块 - 完整修复版"""
	if not is_turret_editing_mode or not current_editing_turret:
		print("❌ 不在炮塔编辑模式或没有当前编辑的炮塔")
		return
	
	if not current_block_scene:
		print("❌ 没有当前块场景")
		return
	
	if not turret_snap_config or turret_snap_config.is_empty():
		print("❌ 没有吸附配置")
		return
	
	print("=== 炮塔编辑模式放置 ===")
	print("吸附配置键:", turret_snap_config)
	
	# 检查必要的键是否存在
	if not turret_snap_config.has("ghost_position"):
		print("❌ 吸附配置缺少位置信息")
		return
	
	# 检查网格位置信息
	var grid_positions = null
	if turret_snap_config.has("grid_positions"):
		grid_positions = turret_snap_config.grid_positions
	elif turret_snap_config.has("positions"):
		grid_positions = turret_snap_config.positions
	else:
		print("❌ 吸附配置缺少网格位置信息")
		print("当前配置:", turret_snap_config)
		return
	
	if not grid_positions or grid_positions.is_empty():
		print("❌ 网格位置为空")
		return
	
	print("✅ 网格位置:", grid_positions)
	
	var new_block: Block = current_block_scene.instantiate()
	
	# 设置碰撞层
	if new_block is CollisionObject2D:
		new_block.set_layer(2)
		new_block.collision_mask = 2
	
	# 使用吸附配置中的位置和旋转
	new_block.global_position = turret_snap_config.ghost_position
	
	# 使用虚影的旋转
	new_block.global_rotation = turret_snap_config.ghost_rotation
	new_block.base_rotation_degree = current_ghost_block.base_rotation_degree
	print("current_ghost_block.global_rotation =", new_block.global_rotation)
	
	# 添加到炮塔
	if turret_snap_config.has("grid_positions"):
		print("✅ 添加块到炮塔，网格位置: ", turret_snap_config.grid_positions)
		current_editing_turret.add_block_to_turret(new_block, turret_snap_config.grid_positions)
	else:
		print("❌ 吸附配置缺少网格位置信息")
		new_block.queue_free()
		return
	
	print("current_ghost_block.global_rotation =", new_block.global_rotation)
	
	# 根据吸附配置类型建立连接
	var connection_established = false
	
	# 等待块准备完成
	if new_block.has_method("connect_aready"):
		await new_block.connect_aready()
	else:
		# 如果没有connect_aready方法，等待一帧
		await get_tree().process_frame
	
	if selected_vehicle:
		selected_vehicle.update_vehicle()
	
	# 重新开始块放置
	start_block_placement_with_rotation(current_block_scene.resource_path)
	
	print("✅ 炮塔块放置完成")
	print("炮塔grid", current_editing_turret.turret_grid)

# === 炮塔检测功能 ===
func has_turret_blocks() -> bool:
	if not selected_vehicle:
		return false
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			if block is TurretRing:
				return true
			if block.get_script() and "TurretRing" in block.get_script().resource_path:
				return true
	
	return false

func get_turret_blocks() -> Array:
	var turrets = []
	if not selected_vehicle:
		return turrets
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			if block is TurretRing:
				turrets.append(block)
			elif block.get_script() and "TurretRing" in block.get_script().resource_path:
				turrets.append(block)
	
	return turrets

func get_turret_at_position(position: Vector2) -> TurretRing:
	var space_state = get_tree().root.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = position
	query.collision_mask = 1
	
	var result = space_state.intersect_point(query)
	for collision in result:
		var block = collision.collider
		if block is TurretRing and block.get_parent() == selected_vehicle:
			return block
	return null

func hide_turret_grid_preview():
	for preview in turret_grid_previews:
		if is_instance_valid(preview):
			preview.queue_free()
	turret_grid_previews.clear()

# === UI 相关函数 ===
func create_tabs():
	for child in tab_container.get_children():
		child.queue_free()
	
	create_tab_with_itemlist("All")
	
	for category in BLOCK_PATHS:
		create_tab_with_itemlist(category)
	
	for tab_name in item_lists:
		item_lists[tab_name].item_selected.connect(_on_item_selected.bind(tab_name))
	
	original_tab_names = []
	for i in range(tab_container.get_tab_count()):
		original_tab_names.append(tab_container.get_tab_title(i))

func create_tab_with_itemlist(tab_name: String):
	var item_list = ItemList.new()
	item_list.name = tab_name
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.max_columns = 0
	item_list.icon_mode = ItemList.ICON_MODE_TOP
	item_list.fixed_column_width = 100
	item_list.fixed_icon_size = Vector2(64, 64)
	item_list.allow_reselect = false
	item_list.allow_search = false
	
	tab_container.add_child(item_list)
	item_lists[tab_name] = item_list

func load_all_blocks():
	var all_blocks = []
	var categorized_blocks = {}
	
	for category in BLOCK_PATHS:
		categorized_blocks[category] = []
		var dir = DirAccess.open(BLOCK_PATHS[category])
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if file_name.ends_with(".tscn"):
					var scene_path = BLOCK_PATHS[category] + file_name
					var scene = load(scene_path)
					var block = scene.instantiate()
					if block is Block:
						all_blocks.append({
							"name": block.block_name,
							"icon": block.get_icon_texture(),
							"path": scene_path
						})
						categorized_blocks[category].append({
							"name": block.block_name,
							"icon": block.get_icon_texture(),
							"path": scene_path
						})
						block.queue_free()
				file_name = dir.get_next()
	
	populate_item_list(item_lists["All"], all_blocks)
	for category in categorized_blocks:
		if item_lists.has(category):
			populate_item_list(item_lists[category], categorized_blocks[category])

func populate_item_list(item_list: ItemList, items: Array):
	item_list.clear()
	for item in items:
		var idx = item_list.add_item(item.name)
		item_list.set_item_icon(idx, item.icon)
		item_list.set_item_metadata(idx, item.path)

func _on_item_selected(index: int, tab_name: String):
	if is_loading_mode:
		var item_list = item_lists[tab_name]
		var vehicle_name = item_list.get_item_text(index)
		load_selected_vehicle(vehicle_name)
	else:
		var item_list = item_lists[tab_name]
		var scene_path = item_list.get_item_metadata(index)
		if scene_path:
			if is_recycle_mode:
				exit_recycle_mode()
			if is_turret_editing_mode:
				start_block_placement(scene_path)
			else:
				emit_signal("block_selected", scene_path)
				update_description(scene_path)
				if is_editing:
					start_block_placement(scene_path)
					update_blueprint_ghosts()

func update_description(scene_path: String):
	var scene = load(scene_path)
	var block = scene.instantiate()
	if block:
		description_label.clear()
		description_label.append_text("[b]%s[/b]\n\n" % block.block_name)
		description_label.append_text("TYPE: %s\n" % block.type)
		description_label.append_text("SIZE: %s\n" % str(block.size))
		if block.has_method("get_description"):
			description_label.append_text("DESCRIPTION: %s\n" % block.get_description())
		block.queue_free()

func _on_build_vehicle_pressed():
	try_save_vehicle()

func switch_to_loading_mode():
	is_loading_mode = true
	load_button.add_theme_color_override("font_color", Color.CYAN)
	
	for tab_name in item_lists:
		item_lists[tab_name].clear()
	
	load_blueprint_vehicles()

func switch_to_normal_mode():
	is_loading_mode = false
	load_button.remove_theme_color_override("font_color")
	
	load_all_blocks()
	
	for i in range(tab_container.get_tab_count()):
		if i < original_tab_names.size():
			tab_container.set_tab_title(i, original_tab_names[i])
	
	clear_blueprint_ghosts()

func load_blueprint_vehicles():
	var blueprint_dir = DirAccess.open(BLUEPRINT["BLUEPRINT"])
	if not blueprint_dir:
		print("错误: 无法打开蓝图目录 ", BLUEPRINT["BLUEPRINT"])
		return
	
	blueprint_dir.list_dir_begin()
	var file_name = blueprint_dir.get_next()
	var vehicle_names = []
	
	while file_name != "":
		if file_name.ends_with(".json"):
			var vehicle_name = file_name.get_basename()
			vehicle_names.append(vehicle_name)
		file_name = blueprint_dir.get_next()
	
	blueprint_dir.list_dir_end()
	
	vehicle_names.sort()
	
	for tab_name in item_lists:
		var item_list = item_lists[tab_name]
		item_list.clear()
		
		var tab_index = tab_container.get_tab_count() - 1
		for i in range(tab_container.get_tab_count()):
			if tab_container.get_tab_control(i) == item_list:
				tab_index = i
				break
		
		if tab_name == "All":
			tab_container.set_tab_title(tab_index, "Vehicles")
		else:
			tab_container.set_tab_title(tab_index, "")
		
		for vehicle_name in vehicle_names:
			var _idx = item_list.add_item(vehicle_name)

func load_selected_vehicle(vehicle_name: String):
	switch_to_normal_mode()
	
	var blueprint_path = BLUEPRINT["BLUEPRINT"] + vehicle_name + ".json"
	var file = FileAccess.open(blueprint_path, FileAccess.READ)
	
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var parse_result = json.parse(json_string)
		
		if parse_result == OK:
			var blueprint_data_ghost = json.data
			show_blueprint_ghosts(blueprint_data_ghost)
			
		else:
			print("错误: 无法解析JSON文件 ", blueprint_path)
	else:
		print("错误: 无法打开文件 ", blueprint_path)

func show_blueprint_ghosts(blueprint: Dictionary):
	if not selected_vehicle:
		print("错误: 没有选中的车辆")
		return
	
	if blueprint.size() == 0:
		return
	
	clear_blueprint_ghosts()
	
	blueprint_data = blueprint
	is_showing_blueprint = true
	
	var current_block_positions = {}
	
	for block in selected_vehicle.total_blocks:
		if is_instance_valid(block):
			var block_grid_positions = get_block_grid_positions(block)
			for grid_pos in block_grid_positions:
				current_block_positions[grid_pos] = block
	
	var created_ghosts = 0
	var total_blueprint_blocks = 0
	
	for block_id in blueprint["blocks"]:
		total_blueprint_blocks += 1
		var block_data = blueprint["blocks"][block_id]
		var scene_path = block_data["path"]
		var base_pos = Vector2i(block_data["base_pos"][0], block_data["base_pos"][1])
		var rotation_deg = block_data["rotation"][0]
		
		var ghost_grid_positions = calculate_ghost_grid_positions(base_pos, rotation_deg, scene_path)
		
		var is_missing = false
		for grid_pos in ghost_grid_positions:
			if not current_block_positions.has(grid_pos):
				is_missing = true
				break
		
		if is_missing:
			create_ghost_block_with_data(scene_path, rotation_deg, ghost_grid_positions)
			created_ghosts += 1

func calculate_ghost_grid_positions(base_pos: Vector2i, rotation_deg: float, scene_path: String) -> Array:
	var scene = load(scene_path)
	if not scene:
		print("错误: 无法加载场景 ", scene_path)
		return []
	
	var temp_block = scene.instantiate()
	var block_size = Vector2i(1, 1)
	if temp_block is Block:
		block_size = temp_block.size
	else:
		temp_block.queue_free()
		return []
	
	temp_block.queue_free()
	
	var grid_positions = []
	
	for x in range(block_size.x):
		for y in range(block_size.y):
			var grid_pos: Vector2i
			
			match int(rotation_deg):
				0:
					grid_pos = base_pos + Vector2i(x, y)
				90:
					grid_pos = base_pos + Vector2i(-y, x)
				-90:
					grid_pos = base_pos + Vector2i(y, -x)
				180, -180:
					grid_pos = base_pos + Vector2i(-x, -y)
				_:
					grid_pos = base_pos + Vector2i(x, y)
			
			grid_positions.append(grid_pos)
	
	return grid_positions

func get_block_grid_positions(block: Block) -> Array:
	var grid_positions = []
	
	for grid_pos in selected_vehicle.grid:
		if selected_vehicle.grid[grid_pos] == block:
			grid_positions.append(grid_pos)
	
	return grid_positions

func get_rectangle_corners_arry(grid_data):
	if grid_data.is_empty():
		return []
	
	var x_coords = []
	var y_coords = []
	
	for coord in grid_data:
		x_coords.append(coord[0])
		y_coords.append(coord[1])
	
	x_coords.sort()
	y_coords.sort()
	
	var min_x = x_coords[0]
	var max_x = x_coords[x_coords.size() - 1]
	var min_y = y_coords[0]
	var max_y = y_coords[y_coords.size() - 1]
	
	var vc_1 = Vector2(min_x * GRID_SIZE , min_y * GRID_SIZE)
	var vc_2 = Vector2(max_x * GRID_SIZE + GRID_SIZE, max_y * GRID_SIZE + GRID_SIZE)
	
	var pos = (vc_1 + vc_2)/2
	
	return pos

func create_ghost_block_with_data(scene_path: String, rotation_deg: float, grid_positions: Array):
	var scene = load(scene_path)
	if not scene:
		print("错误: 无法加载块场景: ", scene_path)
		return
	
	var ghost = scene.instantiate()
	get_tree().current_scene.add_child(ghost)
	
	ghost.modulate = GHOST_BLUEPRINT_COLOR
	ghost.z_index = 45
	ghost.visible = true
	
	var ghost_world_position = calculate_ghost_world_position_precise(grid_positions)
	ghost.global_position = ghost_world_position[0]
	ghost.global_rotation = ghost_world_position[1] + deg_to_rad(rotation_deg)
	
	if ghost.has_method("set_base_rotation_degree"):
		ghost.base_rotation_degree = rotation_deg
	
	setup_blueprint_ghost_collision(ghost)
	
	var data = GhostData.new()
	data.grid_positions = grid_positions
	data.rotation_deg = rotation_deg
	ghost_data_map[ghost.get_instance_id()] = data
	
	blueprint_ghosts.append(ghost)

func calculate_ghost_world_position_precise(grid_positions: Array):
	if grid_positions.is_empty():
		return Vector2.ZERO
	
	var local_position = get_rectangle_corners_arry(grid_positions)
	
	if not selected_vehicle.grid.is_empty():
		var first_grid_pos = selected_vehicle.grid.keys()[0]
		var first_block = selected_vehicle.grid[first_grid_pos]
		var first_gird = []
		for key in selected_vehicle.grid.keys():
			if selected_vehicle.grid[key] == first_block:
				if not first_gird.has(key):
					first_gird.append(key)
		if first_block is Block:
			var first_rotation = deg_to_rad(rad_to_deg(first_block.global_rotation) - first_block.base_rotation_degree)
			
			var first_position = get_rectangle_corners_arry(first_gird)
			
			if first_block:
				
				var local_offset = local_position - first_position
				
				var rotated_offset = local_offset.rotated(first_rotation)
				
				return [first_block.global_position + rotated_offset, first_rotation]
		
	return calculate_ghost_world_position_simple(grid_positions)

func calculate_ghost_world_position_simple(grid_positions: Array) -> Vector2:
	if grid_positions.is_empty():
		return Vector2.ZERO
	
	var sum_x = 0
	var sum_y = 0
	for pos in grid_positions:
		sum_x += pos.x
		sum_y += pos.y
	
	var center_grid = Vector2(sum_x / float(grid_positions.size()), sum_y / float(grid_positions.size()))
	
	var grid_size = 16
	var local_center = Vector2(center_grid.x * grid_size, center_grid.y * grid_size)
	
	return selected_vehicle.to_global(local_center)

func setup_blueprint_ghost_collision(ghost: Node2D):
	var collision_shapes = ghost.find_children("*", "CollisionShape2D", true)
	for shape in collision_shapes:
		shape.disabled = true
	
	var collision_polygons = ghost.find_children("*", "CollisionPolygon2D", true)
	for poly in collision_polygons:
		poly.disabled = true
	
	if ghost is RigidBody2D:
		ghost.freeze = true
		ghost.collision_layer = 0
		ghost.collision_mask = 0
	
	if ghost is Block:
		ghost.do_connect = false
	
	var connection_points = ghost.find_children("*", "Connector", true)
	for point in connection_points:
		if point.has_method("set_connection_enabled"):
			point.set_connection_enabled(false)
			
func get_ghost_data(ghost: Node2D) -> GhostData:
	return ghost_data_map.get(ghost.get_instance_id())

func update_ghosts_transform():
	if not is_showing_blueprint or blueprint_ghosts.is_empty():
		return
	
	for ghost in blueprint_ghosts:
		if is_instance_valid(ghost):
			var ghost_data = get_ghost_data(ghost)
			if ghost_data:
				var new_position = calculate_ghost_world_position_precise(ghost_data.grid_positions)
				ghost.global_position = new_position[0]
				ghost.global_rotation = new_position[1] + deg_to_rad(ghost_data.rotation_deg)

func clear_blueprint_ghosts():
	for ghost in blueprint_ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	blueprint_ghosts.clear()
	ghost_data_map.clear()
	is_showing_blueprint = false

func update_blueprint_ghosts():
	if is_showing_blueprint and selected_vehicle and blueprint_data:
		show_blueprint_ghosts(blueprint_data)

func toggle_blueprint_display():
	if is_editing and selected_vehicle:
		if is_showing_blueprint:
			clear_blueprint_ghosts()
		else:
			if selected_vehicle.blueprint is Dictionary:
				show_blueprint_ghosts(selected_vehicle.blueprint)
			elif selected_vehicle.blueprint is String:
				var blueprint_path = BLUEPRINT["BLUEPRINT"] + selected_vehicle.blueprint + ".json"
				var file = FileAccess.open(blueprint_path, FileAccess.READ)
				if file:
					var json_string = file.get_as_text()
					file.close()
					var json = JSON.new()
					if json.parse(json_string) == OK:
						show_blueprint_ghosts(json.data)
					else:
						print("错误: 无法解析蓝图文件")
				else:
					print("错误: 无法打开蓝图文件")

func try_save_vehicle():
	var vehicle_name = name_input.text.strip_edges()
	
	if vehicle_name.is_empty():
		show_error_dialog("Name cannot be empty!")
		return
	
	if vehicle_name.contains("/") or vehicle_name.contains("\\"):
		show_error_dialog("The name cannot contain special characters!")
		return
	
	save_vehicle(vehicle_name)

func show_error_dialog(error_message: String):
	error_label.text = error_message
	error_label.show()
	save_dialog.title = "Save Error"
	save_dialog.popup_centered()

func _on_save_confirmed():
	save_dialog.hide()

func _on_save_canceled():
	save_dialog.hide()

func _on_name_input_changed(_new_text: String):
	error_label.hide()

func _on_recycle_button_pressed():
	if is_turret_editing_mode:
		# 在炮塔编辑模式下，切换删除模式但不退出炮塔编辑
		if is_recycle_mode:
			exit_recycle_mode()
		else:
			enter_recycle_mode()
	else:
		# 普通模式下正常切换
		if is_recycle_mode:
			exit_recycle_mode()
		else:
			enter_recycle_mode()

func enter_recycle_mode():
	is_recycle_mode = true
	Input.set_custom_mouse_cursor(preload("res://assets/icons/saw_cursor.png"))
	
	cancel_placement()
	
	# 重要：在进入删除模式时重置块的颜色状态
	if is_turret_editing_mode:
		print("炮塔编辑模式：删除功能已切换到炮塔专用")
		# 在炮塔编辑模式下，确保只有当前编辑炮塔高亮，其他所有块变暗
		reset_all_blocks_color()
	else:
		clear_tab_container_selection()
	
	clear_tab_container_selection()
	
	update_recycle_button()
	emit_signal("recycle_mode_toggled", is_recycle_mode)

func update_recycle_button():
	if is_recycle_mode:
		recycle_button.add_theme_color_override("font_color", Color.RED)
	else:
		recycle_button.remove_theme_color_override("font_color")

func reload_blocks():
	for item_list in item_lists.values():
		item_list.clear()
	load_all_blocks()

# === 编辑器模式功能 ===
func initialize_editor():
	pass

func find_and_select_vehicle():
	var testground = get_tree().current_scene
	if testground:
		var canvas_layer = testground.find_child("CanvasLayer", false, false)
		if canvas_layer:
			var panels = canvas_layer.get_children()
			for item in range(panels.size() - 1, -1, -1):
				if panels[item] is FloatingPanel and panels[item].selected_vehicle != null and panels[item].visible == true:
					panel_instance = panels[item]
					break
	if testground and panel_instance:
		if panel_instance.selected_vehicle:
			selected_vehicle = panel_instance.selected_vehicle
			name_input.text = selected_vehicle.vehicle_name
			return

func enter_editor_mode(vehicle: Vehicle):
	if is_editing:
		exit_editor_mode()
	selected_vehicle = vehicle

	is_editing = true
	
	# 新增：默认进入车体模式
	is_vehicle_mode = true
	update_mode_button_display()
	
	if not is_new_vehicle:
		is_first_block = false
	
	for block in selected_vehicle.get_children():
		if block is Block:
			var have_com = false
			for connect_block in block.get_all_connected_blocks():
				if connect_block is Command or block is Command:
					have_com = true
			if have_com == false:
				selected_vehicle.remove_block(block, true)
			
	camera.focus_on_vehicle(selected_vehicle)
	camera.sync_rotation_to_vehicle(selected_vehicle)
	
	enable_all_connection_points_for_editing(true)
	
	vehicle.control = Callable()
	
	show()
	
	current_ghost_connection_index = 0
	current_vehicle_connection_index = 0
	
	toggle_blueprint_display()

func exit_editor_mode():
	if not is_editing:
		return
	
	# 新增：退出时重置模式
	is_vehicle_mode = true
	update_mode_button_display()
	
	if is_turret_editing_mode:
		exit_turret_editing_mode()
	
	if selected_vehicle.check_and_regroup_disconnected_blocks() or selected_vehicle.commands.size() == 0:
		error_label.show()
		if selected_vehicle.check_and_regroup_disconnected_blocks():
			if selected_vehicle.commands.size() == 0:
				error_label.text = "Unconnected Block & No Command"
			else:
				error_label.text = "Unconnected Block"
		else:
			error_label.text = "No Command"
		save_dialog.show()
		save_dialog.title = "Error"
		save_dialog.popup_centered()
		return
	
	for block:Block in selected_vehicle.blocks:
		block.modulate = Color.WHITE
	
	is_new_vehicle = false
	is_first_block = true
	
	if is_recycle_mode:
		exit_recycle_mode()
	
	clear_tab_container_selection()
 	
	restore_original_connections()
	if is_recycle_mode:
		is_recycle_mode = false
		Input.set_custom_mouse_cursor(null)
	
	if current_ghost_block:
		current_ghost_block.queue_free()
		current_ghost_block = null
	
	clear_blueprint_ghosts()
	
	camera.target_rot = 0.0
	
	hide()
	is_editing = false
	panel_instance = null
	selected_vehicle = null

func enable_all_connection_points_for_editing(open: bool):
	if not selected_vehicle:
		return
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			for point in block.connection_points:
				if is_instance_valid(point):
					point.set_connection_enabled(open)

func restore_original_connections():
	if not selected_vehicle:
		return
	
	enable_all_connection_points_for_editing(false)
	await get_tree().process_frame

func start_block_placement(scene_path: String):
	if not is_editing or not selected_vehicle:
		return
	
	if current_ghost_block:
		current_ghost_block.queue_free()
		current_ghost_block = null
	
	current_block_scene = load(scene_path)
	if not current_block_scene:
		push_error("Unable to load block scene: ", scene_path)
		return
	
	current_ghost_block = current_block_scene.instantiate()
	get_tree().current_scene.add_child(current_ghost_block)
	current_ghost_block.modulate = Color(1, 1, 1, 0.5)
	current_ghost_block.z_index = 100
	current_ghost_block.do_connect = false
	
	# 在炮塔编辑模式下设置碰撞层
	if is_turret_editing_mode:
		if current_ghost_block is CollisionObject2D:
			current_ghost_block.set_layer(2)
			current_ghost_block.collision_mask = 2
	
	current_ghost_block.base_rotation_degree = 0
	current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	
	setup_ghost_block_collision(current_ghost_block)
	
	current_ghost_connection_index = 0
	current_vehicle_connection_index = 0
	current_snap_config = {}
	turret_snap_config = {}

func setup_ghost_block_collision(ghost: Node2D):
	var collision_shapes = ghost.find_children("*", "CollisionShape2D", true)
	for shape in collision_shapes:
		shape.disabled = true
	
	var collision_polygons = ghost.find_children("*", "CollisionPolygon2D", true)
	for poly in collision_polygons:
		poly.disabled = true
	
	if ghost is RigidBody2D:
		ghost.freeze = true
		ghost.collision_layer = 0
		ghost.collision_mask = 0

# === 连接点吸附系统 ===
func update_ghost_block_position(mouse_position: Vector2):
	if is_first_block and is_new_vehicle:
		current_ghost_block.global_position = mouse_position
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
		current_ghost_block.modulate = Color(0.8, 0.8, 1.0, 0.5)
		current_snap_config = {}
		return
	
	available_vehicle_points = selected_vehicle.get_available_points_near_position(mouse_position, 20.0)
	available_ghost_points = get_ghost_block_available_connection_points()
	
	if available_vehicle_points.is_empty() or available_ghost_points.is_empty():
		current_ghost_block.global_position = mouse_position
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
		current_ghost_block.modulate = GHOST_FREE_COLOR
		current_snap_config = {}
		return
	
	snap_config = get_current_snap_config()
	
	if snap_config:
		current_ghost_block.global_position = snap_config.ghost_position
		current_ghost_block.global_rotation = snap_config.ghost_rotation
		current_ghost_block.modulate = GHOST_SNAP_COLOR
		current_snap_config = snap_config
	else:
		current_ghost_block.global_position = mouse_position
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
		current_ghost_block.modulate = GHOST_FREE_COLOR
		current_snap_config = {}

func get_ghost_block_available_connection_points() -> Array[Connector]:
	var points: Array[Connector] = []
	if current_ghost_block:
		var connection_points = current_ghost_block.get_available_connection_points()
		for point in connection_points:
			if point is Connector:
				point.qeck = false
				points.append(point)
	return points

func get_current_snap_config() -> Dictionary:
	if available_vehicle_points.is_empty() or available_ghost_points.is_empty():
		return {}
	var best_config = find_best_snap_config()
	return best_config

func find_best_snap_config() -> Dictionary:
	var best_config = {}
	var min_distance = INF
	var best_ghost_pos = null
	var best_vehicle_pos = null
	for vehicle_point in available_vehicle_points:
		var vehicle_block = vehicle_point.find_parent_block()
		if not vehicle_block:
			continue			
		var vehicle_point_global = get_connection_point_global_position(vehicle_point, vehicle_block)
		for ghost_point in available_ghost_points:
			var target_rotation = calculate_aligned_rotation_from_base(vehicle_block)
			if not can_points_connect_with_rotation(vehicle_point, ghost_point, target_rotation):
				continue
				
			var positions = calculate_rotated_grid_positions(vehicle_point, ghost_point)
			if positions is bool:
				continue
			var ghost_local_offset = ghost_point.position.rotated(target_rotation)
			var ghost_position = vehicle_point_global - ghost_local_offset
			var mouse_pos = get_viewport().get_mouse_position()
			var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
			var distance = global_mouse_pos.distance_to(ghost_position)
			if distance < min_distance:
				best_vehicle_pos = vehicle_point
				best_ghost_pos = ghost_point
				min_distance = distance
				best_config = {
					"vehicle_point": vehicle_point,
					"ghost_point": ghost_point,
					"ghost_position": ghost_position,
					"ghost_rotation": target_rotation,
					"vehicle_block": vehicle_block,
					"positions":positions
				}
	
	return best_config

func calculate_aligned_rotation_from_base(vehicle_block: Block) -> float:
	var dir = vehicle_block.base_rotation_degree
	return deg_to_rad(current_ghost_block.base_rotation_degree) + deg_to_rad(-dir) + vehicle_block.global_rotation

func can_points_connect_with_rotation(point_a: Connector, point_b: Connector, ghost_rotation: float) -> bool:
	if point_a.connection_type != point_b.connection_type:
		return false
	if is_editing and is_turret_editing_mode:
		if point_a.layer != 4:
			return false
	if is_editing and not is_turret_editing_mode:
		if point_a.layer != 1:
			return false
	if not point_a.is_connection_enabled or not point_b.is_connection_enabled:
		return false
	var ghost_point_direction = point_b.rotation + ghost_rotation
	var angle_diff = are_rotations_opposite_best(ghost_point_direction, point_a.global_rotation)
	return angle_diff

func are_rotations_opposite_best(rot1: float, rot2: float) -> bool:
	var dir1 = Vector2(cos(rot1), sin(rot1))
	var dir2 = Vector2(cos(rot2), sin(rot2))
	
	var dot_product = dir1.dot(dir2)
	return dot_product < -0.9

func get_connection_point_global_position(point: Connector, block: Block) -> Vector2:
	if block is TurretRing and block.turret_basket and is_turret_editing_mode:
		return block.turret_basket.to_global(point.position)
	else:
		return block.global_position + point.position.rotated(block.global_rotation)

func rotate_ghost_connection():
	if not current_ghost_block:
		return
	
	current_ghost_block.base_rotation_degree += 90
	current_ghost_block.base_rotation_degree = fmod(current_ghost_block.base_rotation_degree + 90, 360) - 90
	
	current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	update_ghost_block_position(global_mouse_pos)

func try_place_block():
	if not current_ghost_block or not selected_vehicle:
		return
	
	if is_first_block and is_new_vehicle:
		place_first_block()
		return
	
	if not current_snap_config:
		return
	
	var connections_to_disconnect = find_connections_to_disconnect_for_placement()
	disconnect_connections(connections_to_disconnect)
	
	var grid_positions = snap_config.positions
	var new_block:Block = current_block_scene.instantiate()
	selected_vehicle.add_child(new_block)
	new_block.global_position = current_snap_config.ghost_position
	new_block.global_rotation = current_ghost_block.global_rotation
	new_block.base_rotation_degree = current_ghost_block.base_rotation_degree
	var control = selected_vehicle.control
	selected_vehicle._add_block(new_block, new_block.position, grid_positions)
	selected_vehicle.control = control
	
	start_block_placement_with_rotation(current_block_scene.resource_path)
	
	update_blueprint_ghosts()

func place_first_block():
	var new_block:Block = current_block_scene.instantiate()
	selected_vehicle.add_child(new_block)
	new_block.global_position = current_ghost_block.global_position
	new_block.global_rotation = current_ghost_block.global_rotation
	new_block.base_rotation_degree = current_ghost_block.base_rotation_degree
	
	var grid_positions = calculate_free_grid_positions(new_block)
	
	var control = selected_vehicle.control
	selected_vehicle._add_block(new_block, new_block.position, grid_positions)
	selected_vehicle.control = control
	
	is_first_block = false
	
	start_block_placement_with_rotation(current_block_scene.resource_path)

func calculate_free_grid_positions(block: Block) -> Array:
	var grid_positions = []
	var world_pos = block.global_position
	var grid_x = int(round(world_pos.x / GRID_SIZE))
	var grid_y = int(round(world_pos.y / GRID_SIZE))
	
	var block_size = block.size
	for x in range(block_size.x):
		for y in range(block_size.y):
			var grid_pos: Vector2i
			match int(block.base_rotation_degree):
				0:
					grid_pos = Vector2i(grid_x + x, grid_y + y)
				90:
					grid_pos = Vector2i(grid_x - y, grid_y + x)
				-90:
					grid_pos = Vector2i(grid_x + y, grid_y - x)
				180, -180:
					grid_pos = Vector2i(grid_x - x, grid_y - y)
				_:
					grid_pos = Vector2i(grid_x + x, grid_y + y)
			
			grid_positions.append(grid_pos)
	
	return grid_positions

func start_block_placement_with_rotation(scene_path: String):
	if not is_editing or not selected_vehicle:
		return
	
	var base_rotation_degree = current_ghost_block.base_rotation_degree
	
	if current_ghost_block:
		current_ghost_block.queue_free()
		current_ghost_block = null
	
	current_block_scene = load(scene_path)
	if not current_block_scene:
		push_error("无法加载块场景: ", scene_path)
		return
	
	current_ghost_block = current_block_scene.instantiate()
	get_tree().current_scene.add_child(current_ghost_block)
	current_ghost_block.modulate = Color(1, 1, 1, 0.5)
	current_ghost_block.z_index = 100
	current_ghost_block.do_connect = false
	
	# 在炮塔编辑模式下设置碰撞层
	if is_turret_editing_mode:
		if current_ghost_block is CollisionObject2D and current_ghost_block is Block:
			current_ghost_block.set_layer(2)
			current_ghost_block.collision_mask = 2
	
	current_ghost_block.base_rotation_degree = base_rotation_degree
	current_ghost_block.rotation = deg_to_rad(base_rotation_degree)
	
	setup_ghost_block_collision(current_ghost_block)
	
	current_ghost_connection_index = 0
	current_vehicle_connection_index = 0
	current_snap_config = {}
	turret_snap_config = {}

func establish_connection(vehicle_point: Connector, new_block: Block, ghost_point: Connector):
	var new_block_points = new_block.find_children("*", "Connector")
	var target_point = null
	
	for point in new_block_points:
		if point is Connector and point.name == ghost_point.name:
			target_point = point
			break
	
	if target_point is Connector:
		target_point.is_connection_enabled = true
		vehicle_point.try_connect(target_point)
		print("we", vehicle_point.layer)

func calculate_rotated_grid_positions(vehiclepoint, ghostpoint):
	var grid_positions = []
	var grid_block = {}
	
	if not selected_vehicle:
		return grid_positions
	
	var block_size = current_ghost_block.size

	var location_v = vehiclepoint.location
	
	var rotation_b = vehiclepoint.find_parent_block().base_rotation_degree
	var grid_b = {}
	var grid_b_pos = {}
	
	for key in selected_vehicle.grid:
		if selected_vehicle.grid[key] == vehiclepoint.find_parent_block():
			grid_b[key] = selected_vehicle.grid[key]
	
	grid_b_pos = get_rectangle_corners(grid_b)
	var grid_connect_g
	if grid_b_pos.is_empty():
		return false
	var connect_pos_v
	if rotation_b == 0:
		connect_pos_v = Vector2i(grid_b_pos["1"].x + location_v.x, grid_b_pos["1"].y + location_v.y)
	elif rotation_b == -90:
		connect_pos_v = Vector2i(grid_b_pos["4"].x + location_v.y, grid_b_pos["4"].y - location_v.x)
	elif rotation_b == -180 or rotation_b == 180:
		connect_pos_v = Vector2i(grid_b_pos["3"].x - location_v.x, grid_b_pos["3"].y - location_v.y)
	elif rotation_b == 90:
		connect_pos_v = Vector2i(grid_b_pos["2"].x - location_v.y, grid_b_pos["2"].y + location_v.x)
	grid_connect_g = get_connection_offset(connect_pos_v, vehiclepoint.rotation, vehiclepoint.find_parent_block().base_rotation_degree)
	
	if grid_connect_g != null and block_size != null and ghostpoint.location != null:
		grid_block = to_grid(grid_connect_g, block_size, ghostpoint.location)
	
	for pos in grid_block:
		if selected_vehicle.grid.has(pos):
			return false
		grid_positions.append(pos)
	
	return grid_positions

func get_connection_offset(connect_pos_v: Vector2i, _rotation: float, direction: int) -> Vector2i:
	var rounded_rotation_or = round(rad_to_deg(_rotation))
	var rounded_rotation = direction + rounded_rotation_or
	rounded_rotation = wrapf(rounded_rotation, -180, 180)
	
	if rounded_rotation == 0:
		return Vector2i(connect_pos_v.x + 1, connect_pos_v.y)
	elif rounded_rotation == -90:
		return Vector2i(connect_pos_v.x, connect_pos_v.y - 1)
	elif rounded_rotation == -180 or rounded_rotation == 180:
		return Vector2i(connect_pos_v.x - 1, connect_pos_v.y)
	elif rounded_rotation == 90:
		return Vector2i(connect_pos_v.x, connect_pos_v.y + 1)
	
	return connect_pos_v

func get_rectangle_corners(grid_data: Dictionary) -> Dictionary:
	if grid_data.is_empty():
		return {}
	
	var x_coords = []
	var y_coords = []
	
	for coord in grid_data.keys():
		x_coords.append(coord[0])
		y_coords.append(coord[1])
	
	x_coords.sort()
	y_coords.sort()
	
	var min_x = x_coords[0]
	var max_x = x_coords[x_coords.size() - 1]
	var min_y = y_coords[0]
	var max_y = y_coords[y_coords.size() - 1]
	
	var corners = {
		"1": Vector2i(min_x, min_y),
		"2": Vector2i(max_x, min_y),
		"3": Vector2i(max_x, max_y),
		"4": Vector2i(min_x, max_y)
	}
	
	return corners

func to_grid(grid_connect_g: Vector2i, block_size: Vector2i, connect_pos_g: Vector2i) -> Dictionary:
	var grid_block = {}
	for i in block_size.x:
		for j in block_size.y:
			if current_ghost_block.base_rotation_degree == 0:
				var left_up = Vector2i(grid_connect_g.x - connect_pos_g.x, grid_connect_g.y - connect_pos_g.y)
				grid_block[Vector2i(left_up.x + i, left_up.y + j)] = current_ghost_block
			elif current_ghost_block.base_rotation_degree == -90:
				var left_up = Vector2i(grid_connect_g.x - connect_pos_g.y, grid_connect_g.y + connect_pos_g.x)
				grid_block[Vector2i(left_up.x + j, left_up.y - i)] = current_ghost_block
			elif current_ghost_block.base_rotation_degree == -180 or current_ghost_block.base_rotation_degree == 180:
				var left_up = Vector2i(grid_connect_g.x + connect_pos_g.x, grid_connect_g.y + connect_pos_g.y)
				grid_block[Vector2i(left_up.x - i, left_up.y - j)] = current_ghost_block
			elif current_ghost_block.base_rotation_degree == 90:
				var left_up = Vector2i(grid_connect_g.x + connect_pos_g.y, grid_connect_g.y - connect_pos_g.x)
				grid_block[Vector2i(left_up.x - j, left_up.y + i)] = current_ghost_block
	return grid_block

func find_connections_to_disconnect_for_placement() -> Array:
	var connections_to_disconnect = []
	if current_snap_config.vehicle_point and current_snap_config.vehicle_point.connected_to:
		connections_to_disconnect.append({
			"from": current_snap_config.vehicle_point,
			"to": current_snap_config.vehicle_point.connected_to
		})
	return connections_to_disconnect

func disconnect_connections(connections: Array):
	for connection in connections:
		if is_instance_valid(connection.from):
			connection.from.disconnect_joint()
		if is_instance_valid(connection.to):
			connection.to.disconnect_joint()

func get_affected_blocks() -> Array:
	var affected_blocks = []
	if current_snap_config.vehicle_point:
		var parent_block = current_snap_config.vehicle_point.find_parent_block()
		if parent_block:
			affected_blocks.append(parent_block)
	return affected_blocks

func enable_connection_points_for_blocks(blocks: Array):
	for block in blocks:
		if is_instance_valid(block):
			for point in block.connection_points:
				if is_instance_valid(point):
					point.set_connection_enabled(true)

func try_remove_block():
	if not selected_vehicle:
		return
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	var space_state = get_tree().root.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = global_mouse_pos
	query.collision_mask = 1
	
	var result = space_state.intersect_point(query)
	for collision in result:
		var block = collision.collider
		if block is Block and block.get_parent() == selected_vehicle:			
			var block_name = block.block_name
			var connections_to_disconnect = find_connections_for_block(block)
			disconnect_connections(connections_to_disconnect)
			var control = selected_vehicle.control
			selected_vehicle.remove_block(block, true)
			selected_vehicle.control = control
			enable_connection_points_for_blocks(get_affected_blocks_for_removal(block))
			call_deferred("check_vehicle_stability")
			
			update_blueprint_ghosts()
			var block_count_after = selected_vehicle.blocks.size()
			if block_count_after == 0:
				is_first_block = true
				is_new_vehicle = true 
			break

func find_connections_for_block(block: Block) -> Array:
	var connections = []
	for point in block.connection_points:
		if point.connected_to:
			connections.append({
				"from": point,
				"to": point.connected_to
			})
	return connections

func get_affected_blocks_for_removal(removed_block: Block) -> Array:
	var affected_blocks = []
	for point in removed_block.connection_points:
		if point.connected_to:
			var connected_block = point.connected_to.find_parent_block()
			if connected_block:
				affected_blocks.append(connected_block)
	return affected_blocks

func cancel_placement():
	if current_ghost_block:
		current_ghost_block.queue_free()
		current_ghost_block = null
	current_block_scene = null
	current_snap_config = {}
	clear_tab_container_selection()

func get_block_size(block: Block) -> Vector2i:
	if block.has_method("get_size"):
		return block.size
	return Vector2i(1, 1)

func check_connections_from_block(block: Block, checked_blocks: Dictionary):
	if checked_blocks.get(block, false):
		return
	
	checked_blocks[block] = true
	
	for point in block.connection_points:
		if point.connected_to:
			var connected_block = point.connected_to.find_parent_block()
			if connected_block and not checked_blocks.get(connected_block, false):
				check_connections_from_block(connected_block, checked_blocks)

func _on_vehicle_saved(vehicle_name: String):
	save_vehicle(vehicle_name)

func save_vehicle(vehicle_name: String):
	if not selected_vehicle:
		print("Error: No vehicle selected")
		return
	
	var blueprint_data_save = create_blueprint_data(vehicle_name)
	var blueprint_path = "res://vehicles/blueprint/%s.json" % vehicle_name
	
	if save_blueprint(blueprint_data_save, blueprint_path):
		selected_vehicle.vehicle_name = vehicle_name
		selected_vehicle.blueprint = blueprint_data_save
	else:
		show_error_dialog("Failed to save the vehicle")

func create_blueprint_data(vehicle_name: String) -> Dictionary:
	var blueprint_data_save = {
		"name": vehicle_name,
		"blocks": {},
		"vehicle_size": [0, 0],
		"rotation": [0]
	}
	
	var block_counter = 1
	var processed_blocks = {}
	
	var min_x = INF
	var min_y = INF
	var max_x = -INF
	var max_y = -INF
	
	# 计算车辆主体的网格范围
	for grid_pos in selected_vehicle.grid:
		min_x = min(min_x, grid_pos.x)
		min_y = min(min_y, grid_pos.y)
		max_x = max(max_x, grid_pos.x)
		max_y = max(max_y, grid_pos.y)
	
	# 存储所有块（包括炮塔）
	for grid_pos in selected_vehicle.grid:
		var block = selected_vehicle.grid[grid_pos]
		if not processed_blocks.has(block):
			var relative_pos = Vector2i(grid_pos.x - min_x, grid_pos.y - min_y)
			var rotation_str = block.base_rotation_degree
			
			var block_data = {
				"name": block.block_name,
				"path": block.scene_file_path,
				"base_pos": [relative_pos.x, relative_pos.y],
				"rotation": [rotation_str],
			}
			
			# 如果是炮塔，添加炮塔网格信息
			if block is TurretRing and is_instance_valid(block) and block.turret_grid and not block.turret_grid.is_empty():
				block_data["turret_grid"] = create_turret_grid_data(block)
			
			blueprint_data_save["blocks"][str(block_counter)] = block_data
			block_counter += 1
			processed_blocks[block] = true
	
	blueprint_data_save["vehicle_size"] = [max_x - min_x + 1, max_y - min_y + 1]
	return blueprint_data_save

func create_turret_grid_data(turret: TurretRing) -> Dictionary:
	"""创建炮塔网格数据，格式与vehicle的blocks类似，不存储相同的块"""
	var turret_grid_data = {
		"blocks": {},
	}
	
	# 计算炮塔网格的范围
	var min_x = INF
	var min_y = INF
	var max_x = -INF
	var max_y = -INF
	
	for turret_grid_pos in turret.turret_grid:
		min_x = min(min_x, turret_grid_pos.x)
		min_y = min(min_y, turret_grid_pos.y)
		max_x = max(max_x, turret_grid_pos.x)
		max_y = max(max_y, turret_grid_pos.y)
	
	# 存储炮塔上的所有块（排除炮塔座圈本身），不重复存储相同的块
	var turret_block_counter = 1
	var processed_turret_blocks = {}
	
	for turret_grid_pos in turret.turret_grid:
		var turret_block = turret.turret_grid[turret_grid_pos]
		
		# 跳过炮塔座圈本身，只存储附加的块
		if turret_block and turret_block != turret:
			# 如果这个块还没有被处理过
			if not processed_turret_blocks.has(turret_block):
				var relative_pos = turret_grid_pos
				turret_grid_data["blocks"][str(turret_block_counter)] = {
					"name": turret_block.block_name,
					"path": turret_block.scene_file_path,
					"base_pos": [relative_pos.x, relative_pos.y],
					"rotation": [turret_block.base_rotation_degree],
				}
				processed_turret_blocks[turret_block] = str(turret_block_counter)
				turret_block_counter += 1
	
	turret_grid_data["grid_size"] = [max_x - min_x + 1, max_y - min_y + 1]
	return turret_grid_data

func save_blueprint(blueprint_data_save: Dictionary, save_path: String) -> bool:
	var dir = DirAccess.open("res://vehicles/blueprint/")
	if not dir:
		DirAccess.make_dir_absolute("res://vehicles/blueprint/")
	
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(blueprint_data_save, "\t"))
		file.close()
		return true
	else:
		push_error("Failed to save file:", FileAccess.get_open_error())
		return false

func update_recycle_highlight():
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	# 先重置所有块的颜色
	reset_all_blocks_color()
	
	if is_turret_editing_mode:
		# 炮塔编辑模式下的高亮：只高亮炮塔上的块
		var block = get_turret_block_at_position(global_mouse_pos)
		if block:
			block.modulate = RECYCLE_HIGHLIGHT_COLOR
	else:
		# 普通删除模式的高亮
		var space_state = get_tree().root.get_world_2d().direct_space_state
		var query = PhysicsPointQueryParameters2D.new()
		query.position = global_mouse_pos
		query.collision_mask = 1
		
		var result = space_state.intersect_point(query)
		for collision in result:
			var block = collision.collider
			if block is Block and block.get_parent() == selected_vehicle:
				block.modulate = RECYCLE_HIGHLIGHT_COLOR
				break

func reset_all_blocks_color():
	if not selected_vehicle:
		return
	
	# 清除所有现有边框
	clear_all_turret_borders()
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			if is_turret_editing_mode:
				# 炮塔编辑模式下：只有当前编辑炮塔和其上的块保持正常颜色，其他所有块都变暗
				if block == current_editing_turret:
					# 当前编辑的炮塔座圈本身保持正常颜色并添加绿色边框
					block.modulate = Color.WHITE
					add_turret_selection_border(block)  # 添加绿色边框
					# 该炮塔上的所有块也保持正常颜色
					for child in block.turret_basket.get_children():
						if child is Block:
							child.modulate = Color.WHITE
				elif current_editing_turret.turret_blocks.has(block):
					# 当前编辑炮塔上的块保持正常颜色
					block.modulate = Color.WHITE
				else:
					# 其他炮塔座圈变暗
					block.modulate = BLOCK_DIM_COLOR
					# 其他炮塔上的块也变暗
					if block is TurretRing:
						for child in block.turret_basket.get_children():
							if child is Block:
								child.modulate = BLOCK_DIM_COLOR
			else:
				# 非炮塔编辑模式：所有块都恢复正常颜色并移除边框
				block.modulate = Color.WHITE
				# 所有炮塔上的块也恢复正常颜色
				if block is TurretRing:
					for child in block.turret_basket.get_children():
						if child is Block:
							child.modulate = Color.WHITE

# 存储炮塔边框的字典
var turret_selection_borders = {}

func add_turret_selection_border(turret: TurretRing):
	"""为选中的炮塔添加绿色边框"""
	if not turret or not is_instance_valid(turret):
		return
	
	# 如果已经有边框了，先移除
	if turret_selection_borders.has(turret.get_instance_id()):
		remove_turret_selection_border(turret)
	
	# 创建边框节点
	var border = create_selection_border(turret)
	if border:
		# 添加到场景中
		get_tree().current_scene.add_child(border)
		# 存储引用
		turret_selection_borders[turret.get_instance_id()] = border
		
		print("为炮塔添加选择边框: ", turret.block_name)

func remove_turret_selection_border(turret: TurretRing):
	"""移除炮塔的绿色边框"""
	var instance_id = turret.get_instance_id()
	if turret_selection_borders.has(instance_id):
		var border = turret_selection_borders[instance_id]
		if is_instance_valid(border):
			border.queue_free()
		turret_selection_borders.erase(instance_id)

func create_selection_border(turret: TurretRing) -> Node2D:
	"""创建选择边框 - 修复位置问题"""
	var border_container = Node2D.new()
	border_container.name = "TurretSelectionBorder"
	
	var world_position = calculate_border_world_position(turret)
	var border_size = calculate_border_size(turret)
	
	border_container.global_position = world_position
	border_container.global_rotation = turret.global_rotation
	
	var border_width = 1.0
	var border_color = Color.GREEN
	
	# 不再做居中偏移，直接从(0,0)开始绘制
	# 上边
	var top_border = ColorRect.new()
	top_border.size = Vector2(border_size.x, border_width)
	top_border.position = Vector2(0, 0)  # 不再居中
	top_border.color = border_color
	
	# 下边
	var bottom_border = ColorRect.new()
	bottom_border.size = Vector2(border_size.x, border_width)
	bottom_border.position = Vector2(0, border_size.y - border_width)  # 调整位置
	bottom_border.color = border_color
	
	# 左边
	var left_border = ColorRect.new()
	left_border.size = Vector2(border_width, border_size.y)
	left_border.position = Vector2(0, 0)  # 不再居中
	left_border.color = border_color
	
	# 右边
	var right_border = ColorRect.new()
	right_border.size = Vector2(border_width, border_size.y)
	right_border.position = Vector2(border_size.x - border_width, 0)  # 调整位置
	right_border.color = border_color
	
	border_container.add_child(top_border)
	border_container.add_child(bottom_border)
	border_container.add_child(left_border)
	border_container.add_child(right_border)
	
	border_container.z_index = 10
	
	return border_container


func calculate_border_size(turret: TurretRing) -> Vector2:
	"""根据炮塔座圈的size和旋转计算边框尺寸"""
	var grid_size = 16
	var base_size = Vector2(turret.size.x * grid_size, turret.size.y * grid_size)
	
	# 根据基础旋转调整尺寸
	match int(turret.base_rotation_degree):
		90, -90, 270:
			# 旋转90度或-90度时，宽高交换
			return Vector2(base_size.y, base_size.x)
		180, -180:
			# 旋转180度，尺寸不变
			return base_size
		_:
			# 0度或其他情况，使用原始尺寸
			return base_size



func create_border_line(parent: Node2D, from: Vector2, to: Vector2, width: float, color: Color):
	"""创建边框线段"""
	var line = Line2D.new()
	line.points = [from, to]
	line.width = width
	line.default_color = color
	line.antialiased = true
	parent.add_child(line)

func calculate_border_world_position(turret: TurretRing) -> Vector2:
	"""计算边框的世界坐标位置"""
	var grid_size = 16
	var border_size = calculate_border_size(turret)
	
	# 计算边框的中心偏移（让边框中心与炮塔中心对齐）
	var center_offset = border_size * 0.5
	
	# 根据旋转调整偏移
	match int(turret.base_rotation_degree):
		90:
			# 旋转90度：需要调整偏移
			center_offset = Vector2(border_size.y * 0.5, border_size.x * 0.5)
		-90, 270:
			# 旋转-90度：需要调整偏移
			center_offset = Vector2(border_size.y * 0.5, border_size.x * 0.5)
		180, -180:
			# 旋转180度：偏移与0度相同
			center_offset = border_size * 0.5
		_:
			# 0度：正常偏移
			center_offset = border_size * 0.5
	
	# 计算局部位置（从炮塔中心减去一半边框尺寸）
	var local_position = Vector2.ZERO - center_offset
	
	# 转换为世界坐标
	return turret.to_global(local_position)


func update_turret_border_positions():
	"""更新所有炮塔边框的位置（在车辆旋转时调用）"""
	for instance_id in turret_selection_borders:
		var turret = instance_from_id(instance_id)
		var border = turret_selection_borders[instance_id]
		
		if is_instance_valid(turret) and is_instance_valid(border):
			var bounds = turret.get_turret_grid_bounds()
			if not bounds.is_empty():
				var world_position = calculate_border_world_position(turret)
				border.global_position = world_position
				border.global_rotation = turret.global_rotation

func clear_all_turret_borders():
	"""清除所有炮塔边框"""
	for instance_id in turret_selection_borders:
		var border = turret_selection_borders[instance_id]
		if is_instance_valid(border):
			border.queue_free()
	turret_selection_borders.clear()

func instance_from_id(instance_id: int) -> Object:
	"""根据实例ID获取对象实例"""
	return instance_from_id(instance_id)

	
func exit_recycle_mode():
	if is_recycle_mode:
		is_recycle_mode = false
		Input.set_custom_mouse_cursor(null)
		update_recycle_button()
		
		if selected_vehicle:
			reset_all_blocks_color()
		
		if is_turret_editing_mode:
			print("炮塔编辑模式：退出删除模式，保持炮塔编辑")
		else:
			# 普通模式下正常退出
			emit_signal("recycle_mode_toggled", false)

func create_new_vehicle():
	if is_editing:
		exit_editor_mode()
		if is_editing:
			return
	
	var new_vehicle = Vehicle.new()
	new_vehicle.vehicle_name = "NewVehicle_" + str(Time.get_unix_time_from_system())
	new_vehicle.blueprint = {}
	
	if camera:
		new_vehicle.global_position = camera.global_position
	else:
		new_vehicle.global_position = Vector2(500, 300)
	
	var current_scene = get_tree().current_scene
	current_scene.add_child(new_vehicle)
	
	enter_editor_mode_with_new_vehicle(new_vehicle)

func enter_editor_mode_with_new_vehicle(vehicle: Vehicle):
	selected_vehicle = vehicle
	
	is_new_vehicle = true
	is_first_block = true
	
	name_input.text = ""
	
	enter_editor_mode(vehicle)

func clear_tab_container_selection():
	for tab_name in item_lists:
		var item_list = item_lists[tab_name]
		item_list.deselect_all()
		item_list.release_focus()

func _on_repair_button_pressed():
	if not is_editing or not selected_vehicle or not is_showing_blueprint:
		return
	
	repair_blueprint_missing_blocks()

func repair_blueprint_missing_blocks():
	for pos in selected_vehicle.grid.keys():
		var block = selected_vehicle.grid[pos]
		if block is Block:
			if block.current_hp < block.max_hp:
				block.current_hp = block.max_hp
	if not blueprint_data or blueprint_ghosts.is_empty():
		return
	
	var repaired_count = 0
	var failed_count = 0
	
	var occupied_grid_positions = {}
	for grid_pos in selected_vehicle.grid:
		occupied_grid_positions[grid_pos] = true
	
	for ghost in blueprint_ghosts:
		if not is_instance_valid(ghost):
			continue
		
		var ghost_data = get_ghost_data(ghost)
		if not ghost_data:
			continue
		
		var can_place = true
		for grid_pos in ghost_data.grid_positions:
			if occupied_grid_positions.has(grid_pos):
				can_place = false
				break
		
		if can_place:
			if try_place_ghost_block(ghost, ghost_data):
				repaired_count += 1
				for grid_pos in ghost_data.grid_positions:
					occupied_grid_positions[grid_pos] = true
			else:
				failed_count += 1
	
	if repaired_count > 0:
		update_blueprint_ghosts()

func try_place_ghost_block(ghost: Node2D, ghost_data: GhostData) -> bool:
	var scene_path = ghost.scene_file_path
	if not scene_path or scene_path.is_empty():
		return false
	
	var scene = load(scene_path)
	if not scene:
		return false
	
	var new_block: Block = scene.instantiate()
	selected_vehicle.add_child(new_block)
	
	new_block.global_position = ghost.global_position
	new_block.global_rotation = ghost.global_rotation
	new_block.base_rotation_degree = ghost_data.rotation_deg
	
	var control = selected_vehicle.control
	selected_vehicle._add_block(new_block, new_block.position, ghost_data.grid_positions)
	selected_vehicle.control = control
	return true

# === 长按拖拽功能 ===

func get_block_at_position(position: Vector2) -> Block:
	var space_state = get_tree().root.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = position
	query.collision_mask = 1
	
	var result = space_state.intersect_point(query)
	for collision in result:
		var block = collision.collider
		if block is Block and block.get_parent() == selected_vehicle:
			return block
	return null


func get_current_snap_config_for_moving() -> Dictionary:
	if available_vehicle_points.is_empty() or available_ghost_points.is_empty():
		return {}
	
	var original_ghost = current_ghost_block
	current_ghost_block = moving_block_ghost
	
	var best_config = find_best_snap_config()
	
	current_ghost_block = original_ghost
	
	return best_config

func get_moving_ghost_available_connection_points() -> Array[Connector]:
	var points: Array[Connector] = []
	if moving_block_ghost:
		var connection_points = moving_block_ghost.get_available_connection_points()
		for point in connection_points:
			if point is Connector:
				point.qeck = false
				points.append(point)
	return points


func are_grid_positions_available(grid_positions: Array) -> bool:
	for pos in grid_positions:
		if selected_vehicle.grid.has(pos):
			return false
	return true

func find_connections_to_disconnect_for_moving() -> Array:
	var connections_to_disconnect = []
	
	if moving_snap_config and moving_snap_config.has("vehicle_point"):
		var vehicle_point = moving_snap_config.vehicle_point
		if vehicle_point and vehicle_point.connected_to:
			connections_to_disconnect.append({
				"from": vehicle_point,
				"to": vehicle_point.connected_to
			})
	
	return connections_to_disconnect
