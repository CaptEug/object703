class_name RigidBodyConnector
extends Marker2D

# 连接参数
@export var is_connection_enabled := true
@export var connection_range := 10.0
@export var connection_type := "rigidbody"
@export var location := Vector2i()

var connected_to: RigidBodyConnector = null
var joint: Joint2D = null
var detection_area: Area2D
var overlapping_connectors: Array[RigidBodyConnector] = []

func _ready():
	setup_detection_area()
	queue_redraw()

func setup_detection_area():
	detection_area = Area2D.new()
	
	# 设置碰撞层和掩码
	detection_area.collision_layer = 0  # 自己不参与碰撞
	detection_area.collision_mask = 8   # 检测第4层（我们专门为连接器设置的层）
	
	print("🔧 设置检测区域 - 连接器: ", name)
	print("   父节点: ", get_parent().name)
	print("   父节点类型: ", ("Block" if is_attached_to_block() else "RigidBody"))
	print("   检测掩码: ", detection_area.collision_mask)
	print("   父节点碰撞层: ", get_parent_collision_layer())
	
	var collider = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = connection_range
	collider.shape = shape
	detection_area.add_child(collider)
	
	# 设置检测区域也在第4层，这样其他连接器能检测到它
	detection_area.collision_layer = 8  # 自己在第4层
	
	add_child(detection_area)
	
	# 连接信号
	detection_area.connect("area_entered", Callable(self, "_on_area_entered"))
	detection_area.connect("area_exited", Callable(self, "_on_area_exited"))
	
	print("✅ 检测区域设置完成")

func _on_area_entered(area: Area2D):
	print("\n🎯 检测到区域进入!")
	print("   检测区域: ", area.name)
	print("   区域父节点: ", area.get_parent().name if area.get_parent() else "无")
	
	var other_connector = area.get_parent()
	if other_connector is RigidBodyConnector:
		print("✅ 找到有效连接器: ", other_connector.name)
		print("   自身类型: ", get_connector_type())
		print("   对方类型: ", other_connector.get_connector_type())
		
		if other_connector != self:
			if not overlapping_connectors.has(other_connector):
				overlapping_connectors.append(other_connector)
				print("📝 添加到重叠列表，尝试连接...")
				try_connect(other_connector)
			else:
				print("⚠️ 已在重叠列表中")
		else:
			print("❌ 检测到自身，忽略")
	else:
		print("❌ 不是RigidBodyConnector，父节点类型: ", area.get_parent().get_class())

func _on_area_exited(area: Area2D):
	print("区域退出: ", area.name)
	var other_connector = area.get_parent()
	if other_connector is RigidBodyConnector:
		if other_connector in overlapping_connectors:
			overlapping_connectors.erase(other_connector)
			print("从重叠列表中移除: ", other_connector.name)

func try_connect(other_connector: RigidBodyConnector) -> bool:
	print("\n🔗 尝试连接过程开始")
	print("   自身: ", name, " (", get_connector_type(), ")")
	print("   对方: ", other_connector.name, " (", other_connector.get_connector_type(), ")")
	
	if not is_connection_enabled:
		print("❌ 自身连接未启用")
		return false
	
	if connected_to != null:
		print("❌ 自身已连接到: ", connected_to.name)
		return false
	
	if not other_connector.is_connection_enabled:
		print("❌ 对方连接未启用")
		return false
	
	if other_connector.connected_to != null:
		print("❌ 对方已连接到: ", other_connector.connected_to.name)
		return false
	
	if not can_connect_with(other_connector):
		print("❌ 连接条件不满足")
		return false
	
	# 确定哪个是block，哪个是rigidbody
	var block_connector = self if is_attached_to_block() else other_connector
	var rigidbody_connector = self if is_attached_to_rigidbody() else other_connector
	
	print("   Block连接器: ", block_connector.name)
	print("   RigidBody连接器: ", rigidbody_connector.name)
	
	# 确保一个是block，一个是rigidbody
	if block_connector == rigidbody_connector:
		print("❌ 错误：两个连接器类型相同")
		return false
	
	var block = block_connector.find_parent_block()
	var rigidbody = rigidbody_connector.get_parent_rigidbody()
	
	if not block:
		print("❌ 未找到Block父节点")
		return false
	
	if not rigidbody:
		print("❌ 未找到RigidBody父节点")
		return false
	
	print("✅ 找到有效配对")
	print("   Block: ", block.name, " (层", block.collision_layer, ")")
	print("   RigidBody: ", rigidbody.name, " (层", rigidbody.collision_layer, ")")
	
	# 创建连接
	connected_to = other_connector
	other_connector.connected_to = self
	
	# 使用block的连接方法
	print("🔧 创建物理关节...")
	joint = BlockPinJoint2D.connect_to_rigidbody(block, rigidbody, block_connector)
	
	if joint:
		# 在另一个连接器中也记录joint
		other_connector.joint = joint
		print("🎉 ✅ 点对点连接成功: ", block.name, " <-> ", rigidbody.name)
		queue_redraw()
		other_connector.queue_redraw()
		return true
	else:
		print("💥 ❌ 关节创建失败")
		connected_to = null
		other_connector.connected_to = null
		return false

func can_connect_with(other_connector: RigidBodyConnector) -> bool:
	print("\n🔍 详细连接条件检查:")
	
	if connected_to != null:
		print("❌ 自身已连接")
		return false
	
	if other_connector.connected_to != null:
		print("❌ 对方已连接")
		return false
	
	# 检查连接类型是否匹配
	if connection_type != other_connector.connection_type:
		print("❌ 连接类型不匹配")
		print("   自身类型: ", connection_type)
		print("   对方类型: ", other_connector.connection_type)
		return false
	
	# 检查距离
	var distance = global_position.distance_to(other_connector.global_position)
	print("📏 距离检查: ", distance, " / ", connection_range)
	if distance > connection_range:
		print("❌ 距离超出范围")
		return false
	else:
		print("✅ 距离在范围内")
	
	# 检查是否一个是Block，一个是RigidBody
	var self_is_block = is_attached_to_block()
	var other_is_block = other_connector.is_attached_to_block()
	
	print("🎯 类型检查:")
	print("   自身是Block: ", self_is_block)
	print("   对方是Block: ", other_is_block)
	
	if self_is_block and other_is_block:
		print("❌ 两个都是Block，不连接")
		return false
	
	if not self_is_block and not other_is_block:
		print("❌ 两个都是RigidBody，不连接")
		return false
	
	print("✅ 类型配对正确 (一个Block，一个RigidBody)")
	
	# 检查碰撞层设置
	var self_layer = get_parent_collision_layer()
	var other_layer = other_connector.get_parent_collision_layer()
	
	print("🛡️ 碰撞层检查:")
	print("   自身层: ", self_layer, " (应该是", (2 if self_is_block else 3), ")")
	print("   对方层: ", other_layer, " (应该是", (2 if other_is_block else 3), ")")
	
	# Block应该在层2，RigidBody应该在层3
	if self_is_block:
		if self_layer != 2:
			print("❌ 自身Block应该在层2，但实际在层", self_layer)
			return false
		else:
			print("✅ 自身Block层正确")
	else:
		if self_layer != 4:
			print("❌ 自身RigidBody应该在层3，但实际在层", self_layer)
			return false
		else:
			print("✅ 自身RigidBody层正确")
	
	if other_is_block:
		if other_layer != 2:
			print("❌ 对方Block应该在层2，但实际在层", other_layer)
			return false
		else:
			print("✅ 对方Block层正确")
	else:
		if other_layer != 3:
			print("❌ 对方RigidBody应该在层3，但实际在层", other_layer)
			return false
		else:
			print("✅ 对方RigidBody层正确")
	
	print("🎉 ✅ 所有连接条件满足!")
	return true

func is_attached_to_block() -> bool:
	var block = get_parent()
	if block is Block:
		block = block
	else:
		block = null
	var result = block != null
	print("   Block检查: ", result, " (", block.name if block else "无", ")")
	return result

func is_attached_to_rigidbody() -> bool:
	var rigidbody = get_parent_rigidbody()
	var result = rigidbody != null
	print("   RigidBody检查: ", result, " (", rigidbody.name if rigidbody else "无", ")")
	return result

func get_connector_type() -> String:
	if is_attached_to_block():
		return "Block"
	elif is_attached_to_rigidbody():
		return "RigidBody"
	else:
		return "Unknown"

func get_parent_collision_layer() -> int:
	var parent = get_parent()
	if parent is CollisionObject2D:
		var layer = (parent as CollisionObject2D).collision_layer
		return layer
	return 0

func find_parent_block() -> Block:
	var parent = get_parent()
	while parent:
		if parent is Block:
			return parent as Block
		parent = parent.get_parent()
	return null

func get_parent_rigidbody() -> RigidBody2D:
	var parent = get_parent()
	if parent is RigidBody2D:
		return parent as RigidBody2D
	return null

# 其余函数保持不变...
func disconnect_connection():
	print("断开连接: ", name)
	if connected_to:
		connected_to.connected_to = null
		connected_to.joint = null
		connected_to.queue_redraw()
		print("已清除对方连接")
	
	if joint and is_instance_valid(joint):
		if joint is BlockPinJoint2D:
			(joint as BlockPinJoint2D).break_connection()
		else:
			joint.queue_free()
		print("已销毁关节")
	
	connected_to = null
	joint = null
	queue_redraw()

func set_connection_enabled(enabled: bool):
	print("设置连接启用: ", name, " -> ", enabled)
	if is_connection_enabled == enabled:
		return
	
	is_connection_enabled = enabled
	
	if not enabled and connected_to:
		disconnect_connection()
	
	queue_redraw()

func is_joint_connected() -> bool:
	return connected_to != null and joint != null and is_instance_valid(joint)

func get_connected_rigidbody() -> RigidBody2D:
	if not connected_to:
		return null
	return connected_to.get_parent_rigidbody()

func get_connected_block() -> Block:
	if not connected_to:
		return null
	return connected_to.find_parent_block()

func get_connection_info() -> String:
	var info = "RigidBodyConnector: " + name + "\n"
	info += "Enabled: " + str(is_connection_enabled) + "\n"
	info += "Connected: " + str(connected_to != null) + "\n"
	info += "Type: " + connection_type + "\n"
	info += "Parent Layer: " + str(get_parent_collision_layer()) + "\n"
	info += "Attached to: " + get_connector_type() + "\n"
	
	if connected_to:
		info += "Connection: " + get_connector_type() + " <-> " + connected_to.get_connector_type() + "\n"
	
	return info

func _draw():
	if Engine.is_editor_hint() or get_tree().debug_collisions_hint:
		var color: Color
		if is_joint_connected():
			color = Color.GREEN
		elif is_connection_enabled:
			color = Color.YELLOW
		else:
			color = Color.RED
		
		# 绘制连接范围圆圈
		draw_arc(Vector2.ZERO, connection_range, 0, TAU, 32, color, 1.0)
		
		# 绘制连接状态指示器
		if is_joint_connected():
			draw_circle(Vector2.ZERO, 3, Color.GREEN)
		else:
			draw_circle(Vector2.ZERO, 2, color)
