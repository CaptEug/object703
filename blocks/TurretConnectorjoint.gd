class_name TurretConnectorJoint
extends PinJoint2D

@export var connection_strength: float = 1.0
@export var lock_rotation: bool = true
@export var maintain_position: bool = true
@export var rotation_stiffness: float = 1.0 
@export var rotation_damping: float = 2.0  
@export var position_stiffness: float = 5.0
@export var position_damping: float = 1.0
@export var max_pull_force: float = 1000.0

var block: Block
var target_body: RigidBody2D
var initial_global_position: Vector2
var connector: TurretConnector
var initial_distance: float = 0.0
var old_v

func _ready():
	setup_joint()

func setup_joint():
	softness = 0.01
	bias = 1
	disable_collision = true

func setup(block_node: Block, target: RigidBody2D, connector_ref: TurretConnector):
	block = block_node
	target_body = target
	connector = connector_ref
	
	# 设置节点路径
	node_a = block.get_path()
	node_b = target.get_path()
	
	# 计算连接点在target本地坐标系中的位置
	var global_connect_pos = connector.global_position
	position = target.to_local(global_connect_pos)
	
	if lock_rotation:
		block.rotation = target.rotation + deg_to_rad(block.base_rotation_degree)

func _physics_process(delta):
	if not is_instance_valid(block) or not is_instance_valid(target_body):
		break_connection()
		return
	
	#if lock_rotation and is_instance_valid(target_body):
		#apply_rotation_constraint(delta)
	
	if not check_connection_strength():
		return

func apply_rotation_constraint(delta: float):
	var body_rid = block.get_rid()
	var body_state = PhysicsServer2D.body_get_direct_state(body_rid)
	var inverse_inertia = body_state.inverse_inertia
	var actual_inertia = 1.0 / inverse_inertia if inverse_inertia > 0 else 0.0
	
	if actual_inertia <= 0:
		return
	
	var target_rotation = target_body.global_rotation + deg_to_rad(block.base_rotation_degree)
	var rotation_diff = wrapf(target_rotation - block.global_rotation, -PI, PI)
	if abs(rotation_diff) < 0.001:
		return
	
	var target_angular_velocity = target_body.angular_velocity
	var angular_velocity_diff = target_angular_velocity - block.angular_velocity
	
	var restoration_torque = rotation_diff * rotation_stiffness * 1000.0 * actual_inertia
	var damping_torque = angular_velocity_diff * rotation_damping * actual_inertia * 100
	var total_torque = restoration_torque + damping_torque
	
	block.apply_torque(total_torque / 10)


func check_connection_strength() -> bool:
	if not maintain_position or initial_distance <= 0:
		return true
	
	var current_distance = block.global_position.distance_to(target_body.global_position)
	var stretch_ratio = current_distance / initial_distance
	
	if stretch_ratio > (1.0 + connection_strength * 0.5):
		print("连接断裂! 拉伸比例: ", stretch_ratio)
		break_connection()
		return false
	
	return true

func break_connection():
	if block and block.joint_connected_blocks.has(self):
		block.joint_connected_blocks.erase(self)
	
	if connector and is_instance_valid(connector):
		connector.disconnect_connection()
	
	queue_free()

# 保持原有参数不变的创建函数
static func connect_to_rigidbody(block: Block, rigidbody: RigidBody2D, connector_ref: TurretConnector, node_a_path: NodePath, lock_rot: bool = true, maintain_pos: bool = true) -> TurretConnectorJoint:
	var joint = TurretConnectorJoint.new()
	joint.lock_rotation = lock_rot
	joint.maintain_position = maintain_pos
	#rigidbody.can_sleep = false
	#block.can_sleep = false
	## 先设置所有属性，再添加为子节点
	joint.node_a = block.get_path()
	joint.node_b = rigidbody.get_path()
	joint.setup(block, rigidbody, connector_ref)
	
	# 最后添加为子节点
	rigidbody.add_child(joint)

	# 然后调用setup进行其他设置
	
	
	# 保持原有的连接关系管理
	var turretring = rigidbody.get_node(node_a_path)
	if turretring is TurretRing:
		if not block.joint_connected_blocks.has(turretring):
			block.joint_connected_blocks[joint] = turretring
		if not turretring.joint_connected_blocks.has(block):
			turretring.joint_connected_blocks[joint] = block
	
	return joint

# 调试方法
func print_rigidbody_state(body: RigidBody2D):
	print("🎯 RigidBody2D 状态:")
	print("  质量: %.2f" % body.mass)
	print("  惯性: %.2f" % body.inertia)
	print("  重力缩放: %.2f" % body.gravity_scale)
	print("  线性速度: %s (长度: %.2f)" % [body.linear_velocity, body.linear_velocity.length()])
	print("  角速度: %.2f rad/s" % body.angular_velocity)
	print("  线性阻尼: %.2f" % body.linear_damp)
	print("  角阻尼: %.2f" % body.angular_damp)
	print("  休眠状态: %s" % body.sleeping)
	print("  是否可以休眠: %s" % body.can_sleep)
	print("  冻结模式: %s" % body.freeze_mode)
	print("  冻结: %s" % body.freeze)
	print("  连续碰撞检测: %s" % body.continuous_cd)
	print("  接触数量: %d" % body.get_contact_count())
	
	if body.get_contact_count() > 0:
		print("  接触点:")
		for i in range(body.get_contact_count()):
			var point = body.get_contact_local_position(i)
			var normal = body.get_contact_local_normal(i)
			print("    %d: 位置%s 法线%s" % [i, point, normal])

# 新增：验证连接状态
func debug_joint_connection():
	print("=== PinJoint连接状态 ===")
	print("父节点:", get_parent().name if get_parent() else "无")
	print("节点A路径:", node_a)
	print("节点B路径:", node_b)
	print("节点A存在:", get_node_or_null(node_a) != null)
	print("节点B存在:", get_node_or_null(node_b) != null)
	print("位置:", position)
	print("软度:", softness)
	print("偏置:", bias)
	print("禁用碰撞:", disable_collision)
	print("锁定旋转:", lock_rotation)
	print("维持位置:", maintain_position)
	print("连接强度:", connection_strength)
	print("=========================")

# 新增：简单连接验证
func is_joint_valid() -> bool:
	var node_a_valid = get_node_or_null(node_a) != null
	var node_b_valid = get_node_or_null(node_b) != null
	var parent_valid = is_instance_valid(get_parent())
	
	return node_a_valid and node_b_valid and parent_valid
