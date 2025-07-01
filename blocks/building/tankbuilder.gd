extends Node2D

# 配置
const GRID_SIZE := 16
@export var factory_size := Vector2i(10, 10)

@export var vehicle_scene: PackedScene = preload("res://vehicles/vehicle.tscn")
@export var builder_ui: PackedScene = preload("res://ui/tankbuilderUI.tscn")

# 建造系统
var current_block_scene: PackedScene
var ghost_block: Node2D
var placed_blocks := {}
var can_build := true
var is_creating_vehicle := false
var is_build_mode := false
var ui_instance: Control

# 背包系统
var inventory = {
	"rusty_track": 5,
	"kwak45": 3,
	"maybach_hl_250": 2
}

func _ready():
	init_ui()
	setup_test_inventory()
	print("信号连接状态：", 
	  ui_instance.is_connected("build_vehicle_requested", self._on_build_vehicle_requested))

func init_ui():
	ui_instance = builder_ui.instantiate()
	add_child(ui_instance)
	ui_instance.hide()
	ui_instance.setup_inventory(inventory)
	ui_instance.block_selected.connect(_on_block_selected)
	ui_instance.build_vehicle_requested.connect(_on_build_vehicle_requested)
	

func setup_test_inventory():
	# 初始化UI显示
	ui_instance.update_inventory_display(inventory)

func _process(delta):
	if ghost_block and not is_creating_vehicle:
		update_ghost_position()
		update_build_indicator()
	if is_creating_vehicle:
		complete_vehicle_creation()

func _input(event):
	handle_build_mode_toggle(event)
	if not is_build_mode or is_creating_vehicle:
		return
	handle_build_actions(event)

func handle_build_mode_toggle(event):
	if event is InputEventKey and event.keycode == KEY_CTRL and event.pressed:
		toggle_build_mode()
	if event is InputEventKey and event.keycode == KEY_TAB and event.pressed:
		toggle_codex_ui()

func handle_build_actions(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			place_block()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			remove_block_at_mouse()

func toggle_build_mode():
	is_build_mode = !is_build_mode
	if is_build_mode:
		enter_build_mode()
	else:
		exit_build_mode()

func enter_build_mode():
	print("进入建造模式")
	ui_instance.build_vehicle_button.visible = true
	create_ghost_block()

func exit_build_mode():
	print("退出建造模式")
	if ghost_block:
		ghost_block.queue_free()
		ghost_block = null
	ui_instance.build_vehicle_button.visible = false

func toggle_codex_ui():
	ui_instance.visible = !ui_instance.visible

func create_ghost_block():
	if not current_block_scene:
		return
		
	if ghost_block:
		ghost_block.queue_free()
	
	ghost_block = current_block_scene.instantiate()
	configure_ghost_block()
	add_child(ghost_block)

func configure_ghost_block():
	ghost_block.modulate = Color(1, 1, 1, 0.5)
	for child in ghost_block.get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", true)
		if child is RigidBody2D:
			child.freeze = true

func update_ghost_position():
	var mouse_pos = get_global_mouse_position()
	var snapped_pos = Vector2(
		floor(mouse_pos.x / GRID_SIZE),
		floor(mouse_pos.y / GRID_SIZE)
	)
	ghost_block.global_position = snapped_pos * GRID_SIZE + ghost_block.size/2 * GRID_SIZE

func place_block():
	if not ghost_block or not can_build:
		return
	
	var block_name = ghost_block.scene_file_path.get_file().get_basename()
	if not inventory.has(block_name) or inventory[block_name] <= 0:
		print("没有足够的", block_name)
		return
	var grid_positions = []
	var world_pos = ghost_block.global_position - ghost_block.size/2 * GRID_SIZE
	var base_pos = Vector2i(
		floor(world_pos.x / GRID_SIZE),
		floor(world_pos.y / GRID_SIZE)
	)
	
	# 计算方块占据的所有网格
	for x in ghost_block.size.x:
		for y in ghost_block.size.y:
			var check_pos = Vector2i(base_pos.x + x, base_pos.y + y)
			grid_positions.append(check_pos)
	
	# 检查重叠
	for pos in grid_positions:
		if placed_blocks.has(pos):
			print("位置被占用: ", pos)
			return
	# 消耗资源
	inventory[block_name] -= 1
	ui_instance.update_inventory_display(inventory)
	
	if inventory[block_name] <= 0:
		inventory.erase(block_name)
		if ghost_block and ghost_block.name == block_name:
			ghost_block.queue_free()
			ghost_block = null
	
	# 放置逻辑
	if is_position_occupied(grid_positions):
		return
	
	var new_block = current_block_scene.instantiate()
	new_block.position = ghost_block.position
	if new_block is RigidBody2D:
		new_block.collision_layer = 2
	add_child(new_block)
	
	for pos in grid_positions:
		placed_blocks[pos] = new_block
	
	create_ghost_block()

func remove_block_at_mouse():
	var mouse_pos = get_global_mouse_position()
	var grid_pos = Vector2i(
		floor(mouse_pos.x / GRID_SIZE),
		floor(mouse_pos.y / GRID_SIZE)
	)
	
	if placed_blocks.has(grid_pos):
		var block = placed_blocks[grid_pos]
		var block_name = block.name
		
		# 返还资源
		if inventory.has(block_name):
			inventory[block_name] += 1
		else:
			inventory[block_name] = 1
		
		ui_instance.update_inventory_display(inventory)
		remove_block_from_grid(block, grid_pos)

func begin_vehicle_creation():
	#print(placed_blocks)
	if placed_blocks.is_empty():
		return
	is_creating_vehicle = true
	

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

# 信号处理
func _on_block_selected(scene_path: String):
	current_block_scene = load(scene_path)
	create_ghost_block()


func _on_build_vehicle_requested():
	if not is_build_mode: return
	begin_vehicle_creation()
	ui_instance.hide()

func update_build_indicator():
	can_build = is_position_in_factory(ghost_block)
	ghost_block.modulate = Color(1, 1, 1, 0.5) if can_build else Color(1, 0.5, 0.5, 0.3)
	
	# 更新按钮状态
	ui_instance.build_vehicle_button.disabled = placed_blocks.is_empty()
	ui_instance.build_vehicle_button.visible = is_build_mode

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

func calculate_grid_positions() -> Array:  # 添加缺失的函数
	var world_pos = ghost_block.global_position - ghost_block.size/2 * GRID_SIZE
	var base_pos = Vector2i(
		floor(world_pos.x / GRID_SIZE),
		floor(world_pos.y / GRID_SIZE)
	)
	
	var positions = []
	for x in ghost_block.size.x:
		for y in ghost_block.size.y:
			positions.append(base_pos + Vector2i(x, y))
	return positions

func is_position_occupied(positions: Array) -> bool:  # 添加缺失的函数
	for pos in positions:
		if placed_blocks.has(pos):
			return true
	return false

func remove_block_from_grid(block: Node, grid_pos: Vector2i):  # 添加缺失的函数
	var positions_to_remove = []
	for pos in placed_blocks:
		if placed_blocks[pos] == block:
			positions_to_remove.append(pos)
	
	for pos in positions_to_remove:
		placed_blocks.erase(pos)
	
	block.queue_free()
