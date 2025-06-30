extends Node2D

# 配置
const GRID_SIZE := 16
@export var factory_size := Vector2i(10, 10)

@export var vehicle_scene: PackedScene = preload("res://vehicles/vehicle.tscn")
@export var builder_ui: PackedScene = preload("res://blocks/building/tankbuilderUI.tscn") 

# 建造系统
var current_block_scene: PackedScene
var current_block_index := 0
var ghost_block: Node2D
var placed_blocks := {}  # {Vector2i 网格坐标: 方块实例}
var can_build := true
var is_creating_vehicle := false
var is_build_mode := false
var ui_instance: Control

func _ready():
	ui_instance = builder_ui.instantiate()
	add_child(ui_instance)
	ui_instance.hide()
	ui_instance.tree.item_selected.connect(_on_codex_block_selected)
	ui_instance.build_vehicle_requested.connect(_on_build_vehicle_requested)
	ui_instance.add_to_inventory("Small Cannon", 5)
	ui_instance.add_to_inventory("Heavy Cannon", 2)
	ui_instance.add_to_inventory("Wheel", 8)
	ui_instance.add_to_inventory("Tank Tread", 4)


func _process(delta):
	if ghost_block and not is_creating_vehicle:
		update_ghost_position()
		update_build_indicator()
	if is_creating_vehicle:
		complete_vehicle_creation()


		
func _input(event):
	if event is InputEventKey and event.keycode == KEY_CTRL:
		if event.pressed:
			toggle_build_mode()
	if event is InputEventKey and event.keycode == KEY_TAB:
		if event.pressed:
			toggle_codex_ui()
	
	if not is_build_mode: return
	if is_creating_vehicle: return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			place_block()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			remove_block_at_mouse()


func toggle_codex_ui():
	if ui_instance.visible:
		ui_instance.hide()
	else:
		ui_instance.show()
		ui_instance.prepare_data()

func toggle_build_mode():
	is_build_mode = !is_build_mode
	
	if is_build_mode:
		print("进入建造模式")
		create_ghost_block()
		ui_instance.build_vehicle_button.visible = true  # 显示按钮
	else:
		print("退出建造模式")
		if ghost_block:
			ghost_block.queue_free()
			ghost_block = null
		ui_instance.build_vehicle_button.visible = false  # 隐藏按钮


# 建造范围检测
func is_position_in_factory(block:Block) -> bool:
   # 计算方块的左上角世界坐标
	var block_top_left = block.global_position - block.size/2 * GRID_SIZE
	
	# 计算方块的右下角世界坐标
	var block_bottom_right = Vector2((block_top_left.x + block.size.x * GRID_SIZE), (block_top_left.y + block.size.y * GRID_SIZE))
	
	# 工厂区域的边界
	var factory_top_left = global_position
	var factory_bottom_right = Vector2((global_position.x + factory_size.x * GRID_SIZE), (global_position.y + factory_size.y * GRID_SIZE))
	
	# 检查是否完全在工厂范围内
	return (block_top_left.x >= factory_top_left.x and
			block_top_left.y >= factory_top_left.y and
			block_bottom_right.x <= factory_bottom_right.x and
			block_bottom_right.y <= factory_bottom_right.y)


# 建造状态指示器
func update_build_indicator():
	if not ghost_block: return
	
	can_build = is_position_in_factory(ghost_block)
	
	# 新增：检查背包中是否有足够的方块
	if ghost_block is Block and not ui_instance.has_in_inventory(ghost_block.block_name):
		can_build = false
		ghost_block.modulate = Color(1, 0.3, 0.3, 0.3)  # 红色表示不能建造
	else:
		ghost_block.modulate = Color(1, 1, 1, 0.5) if can_build else Color(1, 0.5, 0.5, 0.3)
	
	ui_instance.build_vehicle_button.modulate = Color(1, 1, 1) if placed_blocks.size() > 0 else Color(0.5, 0.5, 0.5)


# 幽灵方块管理
func create_ghost_block():
	if not current_block_scene:
		return
		
	if ghost_block:
		ghost_block.queue_free()
	
	ghost_block = current_block_scene.instantiate()
	ghost_block.modulate = Color(1, 1, 1, 0.5)
	
	if ghost_block is Block and not ui_instance.has_in_inventory(ghost_block.block_name):
		ghost_block.queue_free()
		ghost_block = null
		return
	
	# 禁用所有物理行为
	for child in ghost_block.get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", true)
		if child is RigidBody2D:
			child.freeze = true
	
	add_child(ghost_block)

func update_ghost_position():
	var mouse_pos = get_global_mouse_position()
	var world_pos = mouse_pos
	var snapped_pos = Vector2(
		round(world_pos.x / GRID_SIZE),
		round(world_pos.y / GRID_SIZE)
	)
	
	ghost_block.global_position = Vector2(
		(snapped_pos.x * GRID_SIZE),
		(snapped_pos.y * GRID_SIZE)
	)  + ghost_block.size/2 * GRID_SIZE

# 方块放置/删除
func place_block():
	if not ghost_block or not can_build or not current_block_scene: return
	if not ghost_block is Block: return
	
	if not ui_instance.remove_from_inventory(ghost_block.block_name):
		return

	var world_pos = ghost_block.global_position - ghost_block.size/2 * GRID_SIZE
	var snapped_pos = Vector2(
		round(world_pos.x / GRID_SIZE),
		round(world_pos.y / GRID_SIZE)
	)
	
	# 检查是否有重叠
	for x in ghost_block.size.x:
		for y in ghost_block.size.y:
			var check_pos = Vector2((snapped_pos.x + x), (snapped_pos.y + y))
			if placed_blocks.has(check_pos):
				print("位置被占用: ", check_pos)
				return
	
	# 放置新方块
	var new_block = current_block_scene.instantiate()
	new_block.position = ghost_block.position
	
	if new_block is RigidBody2D:
		new_block.collision_layer = 2
	
	add_child(new_block)
	for x in ghost_block.size.x:
		for y in ghost_block.size.y:
			placed_blocks[Vector2((snapped_pos.x + x), (snapped_pos.y + y))] = new_block
	ui_instance.build_vehicle_button.disabled = false
	
	ui_instance.prepare_data()
	create_ghost_block()  # 创建新的幽灵方块


func remove_block_at_mouse():
	var mouse_pos = get_global_mouse_position()
	var world_pos = mouse_pos - ghost_block.size/2 * GRID_SIZE
	var snapped_pos = Vector2(
		round(world_pos.x / GRID_SIZE),
		round(world_pos.y / GRID_SIZE)
	) # 获取鼠标全局坐标
	
	# 遍历所有已放置的方块（优化：使用values()避免重复检查）
	for block_pos in placed_blocks:
		if block_pos == snapped_pos:
			var block = placed_blocks[block_pos]
			if block is Block:
				ui_instance.add_to_inventory(block.block_name)  # 返还到背包
			placed_blocks.erase(block_pos)
			block.queue_free()
			ui_instance.prepare_data()  # 刷新UI显示
			return
	
	print("鼠标位置没有可移除的方块")

# 车辆生成系统
func begin_vehicle_creation():
	if placed_blocks.is_empty():
		print("没有放置方块")
		return
	
	is_creating_vehicle = true
	print("开始生成车辆...")

func complete_vehicle_creation():
	var vehicle = vehicle_scene.instantiate()
	get_parent().add_child(vehicle)
	
	# 转移所有方块到车辆节点
	var processed_blocks = []
	print(placed_blocks)
	for grid_pos in placed_blocks:
		var block = placed_blocks[grid_pos]
		if block in processed_blocks: continue
		if block is RigidBody2D:
			block.collision_layer = 1
	vehicle.bluepirnt = placed_blocks
	vehicle.Get_ready_again()

	
	# 初始化车辆物理
	if vehicle.has_method("initialize_physics"):
		vehicle.initialize_physics(processed_blocks)
	
	placed_blocks.clear() 
	is_creating_vehicle = false
	toggle_build_mode()
	print("车辆生成完成")

func _on_codex_block_selected():
	var selected = ui_instance.tree.get_selected()
	if selected and selected.has_meta("scene_path"):
		current_block_scene = load(selected.get_meta("scene_path"))
		create_ghost_block()


func _on_build_vehicle_requested():
	if not is_build_mode: return
	begin_vehicle_creation()
	ui_instance.hide()
