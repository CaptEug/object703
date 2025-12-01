class_name TankEditor
extends Control

# === 颜色配置变量 ===
@export var GHOST_FREE_COLOR = Color(1, 0.3, 0.3, 0.6)
@export var GHOST_SNAP_COLOR = Color(0.6, 1, 0.6, 0.6)
@export var GHOST_BLUEPRINT_COLOR = Color(0.3, 0.6, 1.0, 0.6)
@export var RECYCLE_HIGHLIGHT_COLOR = Color(1, 0.3, 0.3, 0.6)
@export var BLOCK_DIM_COLOR = Color(0.5, 0.5, 0.5, 0.6)

@onready var tab_container = $TabContainer
@onready var description_label = $Panel/RichTextLabel
@onready var build_vehicle_button = $Panel/SaveButton
@onready var save_dialog = $SaveDialog
@onready var name_input = $Panel/NameInput
@onready var error_label = $SaveDialog/ErrorLabel
@onready var recycle_button = $Panel/DismantleButton
@onready var repair_button = $Panel/RepairButton
@onready var mode_button = $Panel/ModeButton

var saw_cursor:Texture = preload("res://assets/icons/saw_cursor.png")
var panel_instance = null

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

const BLUEPRINT_PATH = "res://vehicles/blueprint/"

# 编辑系统实例
var hull_editing_system: HullEditingSystem
var turret_editing_system: TurretEditingSystem

# UI数据
var item_lists = {}
var is_ui_interaction: bool = false

# 编辑器状态变量
var is_editing := false
var selected_vehicle: Vehicle = null
var camera:Camera2D

# 模式变量
var is_vehicle_mode := true
var is_recycle_mode := false

# 蓝图相关
var blueprint_ghosts := []
var blueprint_data: Dictionary
var is_showing_blueprint := false
var ghost_data_map = {}

# === 重心显示变量 ===
var com_marker: Sprite2D
var com_texture: Texture2D = preload("res://assets/icons/symbls.png")
var com_marker_region: Rect2 = Rect2(224, 32, 16, 16)
var show_center_of_mass: bool = true

func _ready():
	# 初始化编辑系统
	hull_editing_system = HullEditingSystem.new()
	hull_editing_system.setup(self)
	turret_editing_system = TurretEditingSystem.new()
	turret_editing_system.setup(self)
	
	_connect_block_buttons()
	camera = get_tree().current_scene.find_child("Camera2D") as Camera2D
	build_vehicle_button.pressed.connect(_on_build_vehicle_pressed)
	save_dialog.get_ok_button().pressed.connect(_on_save_confirmed)
	save_dialog.close_requested.connect(_on_save_canceled)
	name_input.text_changed.connect(_on_name_input_changed)
	recycle_button.pressed.connect(_on_recycle_button_pressed)
	repair_button.pressed.connect(_on_repair_button_pressed)
	mode_button.pressed.connect(_on_mode_button_pressed)
	create_tabs()
	
	save_dialog.hide()
	error_label.hide()
	
	vehicle_saved.connect(_on_vehicle_saved)
	update_recycle_button()
	load_all_blocks()
	_create_com_marker()
	update_vehicle_info_display()

# === UI管理 ===
func _connect_block_buttons():
	var block_buttons = get_tree().get_nodes_in_group("block_buttons")
	for button in block_buttons:
		if button is BaseButton:
			button.pressed.connect(_on_block_button_pressed)

func _on_block_button_pressed():
	is_ui_interaction = true
	await get_tree().create_timer(0.2).timeout
	is_ui_interaction = false

func create_tabs():
	for child in tab_container.get_children():
		child.queue_free()
	
	create_tab_with_itemlist("All")
	
	for category in BLOCK_PATHS:
		create_tab_with_itemlist(category)
	
	for tab_name in item_lists:
		item_lists[tab_name].item_selected.connect(_on_item_selected.bind(tab_name))

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

func _create_com_marker():
	if com_marker and is_instance_valid(com_marker):
		com_marker.queue_free()
	
	com_marker = Sprite2D.new()
	
	if com_texture:
		if com_marker_region != Rect2(0, 0, 0, 0):
			var atlas_texture = AtlasTexture.new()
			atlas_texture.atlas = com_texture
			atlas_texture.region = com_marker_region
			com_marker.texture = atlas_texture
		else:
			com_marker.texture = com_texture
	
	com_marker.centered = true
	com_marker.visible = false
	com_marker.z_index = -1
	
	add_child(com_marker)

func _update_com_marker():
	if is_editing and selected_vehicle and show_center_of_mass:
		com_marker.visible = true
		com_marker.global_position = _get_com_ui_position()
	else:
		com_marker.visible = false

func _get_com_ui_position() -> Vector2:
	var world_com: Vector2 = selected_vehicle.get_global_mass_center()
	var camera_global_xform: Transform2D = camera.get_global_transform()
	var relative_to_camera: Vector2 = camera_global_xform.affine_inverse() * world_com
	relative_to_camera *= camera.zoom
	var viewport_center: Vector2 = get_viewport().size / 2
	return viewport_center + relative_to_camera

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
	var item_list = item_lists[tab_name]
	var scene_path = item_list.get_item_metadata(index)
	if scene_path:
		if is_recycle_mode:
			exit_recycle_mode()
		if turret_editing_system.is_turret_editing_mode:
			turret_editing_system.start_block_placement(scene_path)
		else:
			emit_signal("block_selected", scene_path)
			update_description(scene_path)
			if is_editing:
				hull_editing_system.start_block_placement(scene_path)
				update_blueprint_ghosts()

func update_description(scene_path: String):
	var scene = load(scene_path)
	var block = scene.instantiate()
	if block:
		_set_font_sizes(16)
		
		description_label.clear()
		description_label.append_text("[b]%s[/b]\n\n" % block.block_name)
		description_label.append_text("TYPE: %s\n" % block.type)
		description_label.append_text("SIZE: %s\n" % str(block.size))
		if block.has_method("get_description"):
			description_label.append_text("DESCRIPTION: %s\n" % block.get_description())
		block.queue_free()

func _set_font_sizes(size: int):
	var font_sizes = ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]
	for font_size in font_sizes:
		description_label.add_theme_font_size_override(font_size, size)

# === 车辆信息显示 ===
func update_vehicle_info_display():
	if not is_editing or not selected_vehicle:
		show_editor_info()
		return
	
	_set_font_sizes(8)
	
	var stats = _calculate_vehicle_stats()
	
	description_label.clear()
	description_label.append_text("Name: %s\n" % (selected_vehicle.vehicle_name if selected_vehicle.vehicle_name else "Unnamed"))
	description_label.append_text("ID: %s\n\n" % selected_vehicle.name)
	description_label.append_text("Weight: %.1f T\n\n" % stats.total_weight)
	description_label.append_text("MAX Engine Power: %.1f kN\n\n" % stats.total_engine_power)
	description_label.append_text("Power/Weight: %.2f kN/T\n\n" % stats.power_to_weight_ratio)

func _calculate_vehicle_stats() -> Dictionary:
	if not selected_vehicle:
		return {}
	
	var total_weight := 0.0
	var total_engine_power := 0.0
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			total_weight += block.mass
			if block is Powerpack:
				total_engine_power += block.max_power
	
	var power_to_weight_ratio = total_engine_power / total_weight if total_weight > 0 else 0.0
	
	return {
		"total_weight": total_weight,
		"total_engine_power": total_engine_power,
		"power_to_weight_ratio": power_to_weight_ratio
	}

func show_editor_info():
	description_label.text = "[b]TankEditor - Vehicle Builder[/b]\n\n"
	description_label.append_text("Hotkeys:\n")
	description_label.append_text("• B: Enter/Exit Edit Mode\n")
	description_label.append_text("• R: Rotate Block\n")
	description_label.append_text("• X: Toggle Delete Mode\n")
	description_label.append_text("• T: Toggle Blueprint Display\n")
	description_label.append_text("• ESC: Cancel Operation\n")
	description_label.append_text("• F: Repair Vehicle\n")
	description_label.append_text("• N: New Vehicle\n")
	description_label.append_text("• L: Load Mode\n\n")
	
	description_label.append_text("[b]Edit Mode[/b]\n")
	if is_vehicle_mode:
		description_label.append_text("Current: Hull Edit Mode\n")
		description_label.append_text("Click turret to edit turret\n")
	else:
		description_label.append_text("Current: Turret Edit Mode\n")
		description_label.append_text("Right-click to exit turret edit\n")

# === 输入处理 ===
func _input(event):
	if event is InputEventKey and event.pressed:
		print("=== 键盘输入 ===")
		_handle_key_input(event)
	elif event is InputEventMouseButton and event.pressed:
		print("=== 鼠标点击 ===")
		print("鼠标按钮: ", event.button_index)
		print("UI交互状态: ", is_ui_interaction)
		print("悬停控件: ", get_viewport().gui_get_hovered_control())
		
		# 首先检查UI交互
		if is_ui_interaction or get_viewport().gui_get_hovered_control():
			print("点击被UI拦截")
			return
		
		print("开始处理游戏内点击")
		_handle_mouse_input(event)


func _handle_key_input(event: InputEventKey):
	print("处理键盘输入，按键: ", event.keycode)
	match event.keycode:
		KEY_B:
			print("B键 - 切换编辑模式")
			_toggle_edit_mode()
		KEY_ESCAPE:
			print("ESC键 - 取消操作")
			_handle_escape_key()
		KEY_R:
			print("R键 - 旋转虚影块")
			_rotate_ghost_block()
		KEY_X:
			print("X键 - 切换回收模式")
			_toggle_recycle_mode()
		KEY_T:
			print("T键 - 切换蓝图显示")
			if is_editing and selected_vehicle:
				toggle_blueprint_display()
		KEY_N:
			print("N键 - 新建车辆")
			if not is_editing:
				create_new_vehicle()
		KEY_F:
			print("F键 - 修复车辆")
			if is_editing and selected_vehicle and is_showing_blueprint:
				repair_blueprint_missing_blocks()

func _handle_mouse_input(event: InputEventMouseButton):
	print("处理鼠标输入")
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			print("左键点击")
			_handle_left_click()
		MOUSE_BUTTON_RIGHT:
			print("右键点击")
			_handle_right_click()


func _handle_left_click():
	print("=== 处理左键点击 ===")
	print("当前模式 - 车辆模式:", is_vehicle_mode, " 炮塔编辑模式:", turret_editing_system.is_turret_editing_mode, " 回收模式:", is_recycle_mode)
	
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	print("鼠标位置 - 屏幕:", mouse_pos, " 全局:", global_mouse_pos)
	
	# 首先检查是否在炮塔编辑模式
	if turret_editing_system.is_turret_editing_mode:
		print("进入炮塔编辑模式点击处理")
		_handle_turret_mode_click(global_mouse_pos)
		return
	
	# 车辆模式下的点击处理
	var clicked_block = get_block_at_position(global_mouse_pos)
	print("点击到的块: ", clicked_block)
	
	# 检查是否点击了炮塔
	if clicked_block is TurretRing and not is_recycle_mode:
		print("点击到炮塔: ", clicked_block.name)
		_handle_turret_click(clicked_block)
	elif not turret_editing_system.is_turret_editing_mode:
		print("调用车体编辑系统处理点击")
		hull_editing_system.handle_left_click()
	else:
		print("调用炮塔编辑系统处理点击")
		turret_editing_system.handle_left_click()

func _handle_turret_mode_click(global_mouse_pos: Vector2):
	"""专门处理炮塔编辑模式下的点击"""
	print("=== 炮塔编辑模式点击处理 ===")
	print("当前编辑的炮塔: ", turret_editing_system.current_editing_turret)
	print("当前虚影块: ", turret_editing_system.current_ghost_block != null)
	
	# 如果有虚影块，尝试放置
	if turret_editing_system.current_ghost_block:
		print("有虚影块，尝试放置")
		turret_editing_system.handle_left_click()
		return
	
	# 检查是否点击了其他炮塔
	var clicked_block = get_block_at_position(global_mouse_pos)
	print("点击到的块: ", clicked_block)
	
	if clicked_block is TurretRing and clicked_block != turret_editing_system.current_editing_turret:
		print("点击到其他炮塔，切换到: ", clicked_block.name)
		_handle_turret_click(clicked_block)
		return
	
	print("默认调用炮塔编辑系统处理点击")
	turret_editing_system.handle_left_click()


func _handle_turret_click(turret: TurretRing):
	print("=== 处理炮塔点击 ===")
	print("点击的炮塔: ", turret.name if turret else "null")
	
	# 确保炮塔有效
	if not turret or not is_instance_valid(turret):
		print("错误: 无效的炮塔")
		return
	
	# 如果已经在编辑这个炮塔，忽略点击
	if turret_editing_system.current_editing_turret == turret:
		print("已经在编辑这个炮塔")
		return
	
	# 如果正在放置虚影块，忽略炮塔切换
	if turret_editing_system.current_ghost_block:
		print("正在放置块，忽略炮塔切换")
		return
	
	print("设置当前编辑炮塔并切换到炮塔模式")
	# 设置当前编辑的炮塔
	turret_editing_system.current_editing_turret = turret
	
	# 切换到炮塔模式
	switch_to_turret_mode()
	
	print("成功进入炮塔编辑模式")


func _handle_right_click():
	if turret_editing_system.is_turret_editing_mode and is_recycle_mode:
		exit_recycle_mode()
		return
	if turret_editing_system.is_turret_editing_mode and turret_editing_system.current_ghost_block == null:
		turret_editing_system.exit_turret_editing_mode()
	elif turret_editing_system.current_ghost_block != null:
		if turret_editing_system.is_turret_editing_mode:
			turret_editing_system.cancel_placement()
	else:
		hull_editing_system.cancel_placement()

func _handle_escape_key():
	if turret_editing_system.is_turret_editing_mode:
		turret_editing_system.exit_turret_editing_mode()
		return
	hull_editing_system.cancel_placement()

func _rotate_ghost_block():
	if hull_editing_system.current_ghost_block:
		hull_editing_system.rotate_ghost_connection()
	elif turret_editing_system.current_ghost_block:
		turret_editing_system.rotate_ghost_connection()

func _process(delta):
	if is_editing and selected_vehicle:
		camera.sync_rotation_to_vehicle(selected_vehicle)
	
	if is_showing_blueprint and not blueprint_ghosts.is_empty():
		update_ghosts_transform()	
	
	if is_editing and is_recycle_mode and selected_vehicle:
		update_recycle_highlight()
	
	_update_com_marker()
	hull_editing_system.process(delta)
	turret_editing_system.process(delta)

# === 模式切换 ===
func _on_mode_button_pressed():
	if not is_editing:
		return
	
	if is_vehicle_mode:
		switch_to_turret_mode()
	else:
		switch_to_vehicle_mode()

func switch_to_turret_mode():
	if not is_editing or not selected_vehicle:
		return
	
	if is_recycle_mode:
		exit_recycle_mode()
	
	hull_editing_system.cancel_placement()
	
	is_vehicle_mode = false
	
	var turrets = get_turret_blocks()
	if turrets.is_empty():
		is_vehicle_mode = true
		update_mode_button_display()
		return
	
	var first_turret = turrets[0]
	turret_editing_system.enter_turret_editing_mode(first_turret)
	update_mode_button_display()

func switch_to_vehicle_mode():
	if not is_editing:
		return
	
	if turret_editing_system.is_turret_editing_mode:
		turret_editing_system.exit_turret_editing_mode()
	
	is_vehicle_mode = true
	update_mode_button_display()

func update_mode_button_display():
	if not mode_button:
		return
	
	if is_vehicle_mode:
		mode_button.tooltip_text = "车体编辑模式 (点击切换到炮塔编辑)"
	else:
		mode_button.tooltip_text = "炮塔编辑模式 (点击切换回车体编辑)"

# === 删除模式 ===
func _on_recycle_button_pressed():
	_toggle_recycle_mode()

func _toggle_recycle_mode():
	if is_recycle_mode:
		exit_recycle_mode()
	else:
		enter_recycle_mode()

func enter_recycle_mode():
	is_recycle_mode = true
	Input.set_custom_mouse_cursor(saw_cursor)
	
	hull_editing_system.cancel_placement()
	turret_editing_system.cancel_placement()
	
	clear_tab_container_selection()
	
	update_recycle_button()
	emit_signal("recycle_mode_toggled", is_recycle_mode)

func exit_recycle_mode():
	if is_recycle_mode:
		is_recycle_mode = false
		Input.set_custom_mouse_cursor(null)
		update_recycle_button()
		
		if selected_vehicle:
			reset_all_blocks_color()
		
		emit_signal("recycle_mode_toggled", false)

func update_recycle_highlight():
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	reset_all_blocks_color()
	
	if turret_editing_system.is_turret_editing_mode:
		var block = turret_editing_system.get_turret_block_at_position(global_mouse_pos)
		if block:
			block.modulate = RECYCLE_HIGHLIGHT_COLOR
	else:
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
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			if turret_editing_system.is_turret_editing_mode:
				turret_editing_system.handle_block_colors_in_turret_mode(block)
			else:
				block.modulate = Color.WHITE
				if block is TurretRing:
					for child in block.turret_basket.get_children():
						if child is Block:
							child.modulate = Color.WHITE

func update_recycle_button():
	if is_recycle_mode:
		recycle_button.add_theme_color_override("font_color", Color.RED)
	else:
		recycle_button.remove_theme_color_override("font_color")

# === 编辑器模式功能 ===
func find_and_select_vehicle():
	var testground = get_tree().current_scene
	if testground:
		var canvas_layer = testground.find_child("CanvasLayer", false, false)
		if canvas_layer:
			var panels = canvas_layer.get_children()
			for i in range(panels.size() - 1, -1, -1):
				if panels[i] is FloatingPanel and panels[i].selected_vehicle != null and panels[i].visible == true:
					panel_instance = panels[i]
					break
	if testground and panel_instance:
		if panel_instance.selected_vehicle:
			selected_vehicle = panel_instance.selected_vehicle
			name_input.text = selected_vehicle.vehicle_name

func enter_editor_mode(vehicle: Vehicle):
	if is_editing:
		exit_editor_mode()
	selected_vehicle = vehicle

	is_editing = true
	is_vehicle_mode = true
	update_mode_button_display()
	
	if not hull_editing_system.is_new_vehicle:
		hull_editing_system.is_first_block = false
	
	_cleanup_invalid_blocks()
	
	camera.focus_on_vehicle(selected_vehicle)
	camera.sync_rotation_to_vehicle(selected_vehicle)
	
	hull_editing_system.enable_all_connection_points_for_editing(true)
	
	vehicle.control = Callable()
	show()
	
	hull_editing_system.reset_connection_indices()
	
	show_center_of_mass = true
	com_marker.visible = true
	
	toggle_blueprint_display()
	update_vehicle_info_display()

func _cleanup_invalid_blocks():
	for block in selected_vehicle.get_children():
		if block is Block and block.collision_layer == 1:
			var has_command = false
			for connected_block in block.get_all_connected_blocks():
				if connected_block is Command or block is Command:
					has_command = true
			if not has_command:
				selected_vehicle.remove_block(block, true)

func _toggle_edit_mode():
	if is_editing:
		exit_editor_mode()
		hull_editing_system.cancel_placement()
		turret_editing_system.cancel_placement()
	else:
		if selected_vehicle == null:
			find_and_select_vehicle()
		if selected_vehicle:
			enter_editor_mode(selected_vehicle)

func exit_editor_mode():
	if not is_editing:
		return
	
	is_vehicle_mode = true
	update_mode_button_display()
	
	if turret_editing_system.is_turret_editing_mode:
		turret_editing_system.exit_turret_editing_mode()
	
	if selected_vehicle.check_and_regroup_disconnected_blocks() or selected_vehicle.commands.size() == 0:
		_show_exit_error_dialog()
		return
	
	for block:Block in selected_vehicle.blocks:
		block.modulate = Color.WHITE
	
	hull_editing_system.is_new_vehicle = false
	hull_editing_system.is_first_block = true
	
	if is_recycle_mode:
		exit_recycle_mode()
	clear_tab_container_selection()
 	
	hull_editing_system.restore_original_connections()
	
	hull_editing_system.cancel_placement()
	
	clear_blueprint_ghosts()
	
	camera.target_rot = 0.0
	
	show_center_of_mass = false
	com_marker.visible = false
	
	hide()
	is_editing = false
	panel_instance = null
	selected_vehicle = null
	update_vehicle_info_display()

func _show_exit_error_dialog():
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

# === 蓝图功能 ===
func toggle_blueprint_display():
	if is_editing and selected_vehicle:
		if is_showing_blueprint:
			clear_blueprint_ghosts()
		else:
			if selected_vehicle.blueprint is Dictionary:
				show_blueprint_ghosts(selected_vehicle.blueprint)
			elif selected_vehicle.blueprint is String:
				load_blueprint_from_file(selected_vehicle.blueprint)

func show_blueprint_ghosts(blueprint: Dictionary):
	if not selected_vehicle or blueprint.size() == 0:
		return
	
	clear_blueprint_ghosts()
	
	blueprint_data = blueprint
	is_showing_blueprint = true
	
	var current_block_positions = _get_current_block_positions()
	var created_ghosts = 0
	
	for block_id in blueprint["blocks"]:
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

func _get_current_block_positions() -> Dictionary:
	var positions = {}
	for grid_pos in selected_vehicle.grid:
		positions[grid_pos] = selected_vehicle.grid[grid_pos]
	return positions

func calculate_ghost_grid_positions(base_pos: Vector2i, rotation_deg: float, scene_path: String) -> Array:
	var scene = load(scene_path)
	if not scene:
		return []
	
	var temp_block = scene.instantiate()
	var block_size = Vector2i(1, 1)
	if temp_block is Block:
		block_size = temp_block.size
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

func create_ghost_block_with_data(scene_path: String, rotation_deg: float, grid_positions: Array):
	var scene = load(scene_path)
	if not scene:
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
		return [Vector2.ZERO, 0.0]
	
	var local_position = get_rectangle_corners(grid_positions)
	
	if not selected_vehicle.grid.is_empty():
		var first_grid_pos = selected_vehicle.grid.keys()[0]
		var first_block = selected_vehicle.grid[first_grid_pos]
		var first_grid = []
		for key in selected_vehicle.grid.keys():
			if selected_vehicle.grid[key] == first_block and not first_grid.has(key):
				first_grid.append(key)
		if first_block is Block:
			var first_rotation = deg_to_rad(rad_to_deg(first_block.global_rotation) - first_block.base_rotation_degree)
			var first_position = get_rectangle_corners(first_grid)
			
			if first_block:
				var local_offset = local_position - first_position
				var rotated_offset = local_offset.rotated(first_rotation)
				return [first_block.global_position + rotated_offset, first_rotation]
	
	return [calculate_ghost_world_position_simple(grid_positions), 0.0]

func calculate_ghost_world_position_simple(grid_positions: Array) -> Vector2:
	if grid_positions.is_empty():
		return Vector2.ZERO
	
	var sum_x = 0
	var sum_y = 0
	for pos in grid_positions:
		sum_x += pos.x
		sum_y += pos.y
	
	var center_grid = Vector2(sum_x / float(grid_positions.size()), sum_y / float(grid_positions.size()))
	var local_center = Vector2(center_grid.x * GRID_SIZE, center_grid.y * GRID_SIZE)
	
	return selected_vehicle.to_global(local_center)

func setup_blueprint_ghost_collision(ghost: Node2D):
	# 禁用碰撞
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

func get_rectangle_corners(grid_data):
	if grid_data.is_empty():
		return Vector2.ZERO
	
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
	
	return (vc_1 + vc_2)/2

# === 修复功能 ===
func _on_repair_button_pressed():
	if not is_editing or not selected_vehicle or not is_showing_blueprint:
		return
	
	repair_blueprint_missing_blocks()

func repair_blueprint_missing_blocks():
	# 修复车辆现有块的HP
	for block in selected_vehicle.blocks:
		if is_instance_valid(block) and block.current_hp < block.max_hp:
			block.current_hp = block.max_hp
	
	if not blueprint_data or blueprint_ghosts.is_empty():
		return
	
	var occupied_grid_positions = {}
	for grid_pos in selected_vehicle.grid:
		occupied_grid_positions[grid_pos] = true
	
	var repaired_count = 0
	
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
		
		if can_place and try_place_ghost_block(ghost, ghost_data):
			repaired_count += 1
			for grid_pos in ghost_data.grid_positions:
				occupied_grid_positions[grid_pos] = true
	
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

func load_blueprint_from_file(blueprint_name: String):
	var blueprint_path = BLUEPRINT_PATH + blueprint_name + ".json"
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

# === 新建车辆功能 ===
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
	hull_editing_system.is_new_vehicle = true
	hull_editing_system.is_first_block = true
	name_input.text = ""
	enter_editor_mode(vehicle)

# === 保存功能 ===
func _on_build_vehicle_pressed():
	try_save_vehicle()

func try_save_vehicle():
	var vehicle_name = name_input.text.strip_edges()
	
	if vehicle_name.is_empty():
		show_error_dialog("Name cannot be empty!")
		return
	
	if vehicle_name.contains("/") or vehicle_name.contains("\\"):
		show_error_dialog("The name cannot contain special characters!")
		return
	
	save_vehicle(vehicle_name)

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
		if turret_block and turret_block != turret and not processed_turret_blocks.has(turret_block):
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

func clear_tab_container_selection():
	for tab_name in item_lists:
		var item_list = item_lists[tab_name]
		item_list.deselect_all()
		item_list.release_focus()

# === 辅助函数 ===
func get_turret_blocks() -> Array:
	var turrets = []
	if not selected_vehicle:
		return turrets
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block) and block is TurretRing:
			turrets.append(block)
	
	return turrets

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

# === 虚影数据类 ===
class GhostData:
	var grid_positions: Array
	var rotation_deg: float
