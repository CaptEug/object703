class_name TurretConnectorJoint
extends PinJoint2D

@export var connection_strength: float = 1.0
@export var lock_rotation: bool = true
@export var maintain_position: bool = true
@export var rotation_stiffness: float = 1.0 
@export var rotation_damping: float = 2.0  
# 新增：位置约束参数
@export var position_stiffness: float = 5.0  # 位置刚度
@export var position_damping: float = 1.0    # 位置阻尼
@export var max_pull_force: float = 1000.0   # 最大拉力

var block: Block
var target_body: RigidBody2D
var initial_global_position: Vector2
var connector: TurretConnector
var initial_distance: float = 0.0  # 初始距离

func _ready():
	setup_joint()

func setup_joint():
	softness = 0.01
	bias = 0
	disable_collision = true

func setup(block_node: Block, target: RigidBody2D, connector_ref: TurretConnector):
	block = block_node
	target_body = target
	connector = connector_ref
	
	#if maintain_position:
		#initial_global_position = block.global_position
		## 计算初始距离
		#initial_distance = block.global_position.distance_to(target.global_position)
	
	node_a = block.get_path()
	node_b = target.get_path()
	
	var local_connect_pos = block.to_local(connector.global_position)
	position = local_connect_pos
	
	if lock_rotation:
		block.rotation = target.rotation + deg_to_rad(block.base_rotation_degree)

func _physics_process(delta):
	if not is_instance_valid(block) or not is_instance_valid(target_body):
		break_connection()
		return
	
	#if lock_rotation and is_instance_valid(target_body):
		#apply_rotation_constraint(delta)
	

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
	var damping_torque = angular_velocity_diff * rotation_damping * actual_inertia * 10
	var total_torque = restoration_torque + damping_torque
	
	block.apply_torque(total_torque)

# 新增：位置约束函数
#func apply_position_constraint(delta: float):
	#if not maintain_position or initial_distance <= 0:
		#return
	#
	## 计算当前距离和方向
	#var current_distance = block.global_position.distance_to(target_body.global_position)
	#var pull_distance = current_distance - initial_distance
	#
	## 如果被拉开的距离很小，忽略
	#if abs(pull_distance) < 1:
		#return
	#
	## 计算拉力方向（从block指向target）
	#var pull_direction = (target_body.global_position - block.global_position).normalized()
	#
	## 计算恢复力（弹簧模型）
	#var restoration_force = -pull_distance * position_stiffness * 100.0
	#
	## 计算相对速度阻尼
	#var relative_velocity = target_body.linear_velocity - block.linear_velocity
	#var velocity_in_pull_direction = relative_velocity.dot(pull_direction)
	#var damping_force = -velocity_in_pull_direction * position_damping * 10.0
	#
	## 合力
	#var total_force = restoration_force + damping_force
	#
	## 限制最大力
	#total_force = clamp(total_force, -max_pull_force * 100, max_pull_force * 100)
	#
	## 应用力（根据距离决定施加在哪个物体上）
	#if pull_distance > 0:
		## block被拉开，向target方向拉block
		#block.apply_central_force(-pull_direction * total_force)
	#else:
		## block被推近，向远离target方向推block
		#block.apply_central_force(pull_direction * total_force)
	#
	## 调试信息（可选）
	#if abs(pull_distance) > 1.0:  # 只有明显拉开时才打印
		#print("位置约束: 距离变化=%.2f, 施加力=%.2f" % [pull_distance, total_force])

# 新增：检查连接强度
func check_connection_strength() -> bool:
	if not maintain_position or initial_distance <= 0:
		return true
	
	var current_distance = block.global_position.distance_to(target_body.global_position)
	var stretch_ratio = current_distance / initial_distance
	
	# 如果拉伸超过阈值，断开连接
	if stretch_ratio > (1.0 + connection_strength * 0.5):
		print("连接断裂! 拉伸比例: ", stretch_ratio)
		break_connection()
		return false
	
	return true

func break_connection():
	# 在断开前进行最后一次检查
	if block and block.joint_connected_blocks.has(self):
		block.joint_connected_blocks.erase(self)
	
	if connector and is_instance_valid(connector):
		connector.disconnect_connection()
	
	queue_free()

static func connect_to_rigidbody(block: Block, rigidbody: RigidBody2D, connector_ref: TurretConnector, node_a_path: NodePath, lock_rot: bool = true, maintain_pos: bool = true) -> TurretConnectorJoint:
	var joint = TurretConnectorJoint.new()
	joint.lock_rotation = lock_rot
	joint.maintain_position = maintain_pos
	joint.setup(block, rigidbody, connector_ref)
	block.add_child(joint)
	
	var turretring = rigidbody.get_node(node_a_path)
	if turretring is TurretRing:
		if not block.joint_connected_blocks.has(turretring):
			block.joint_connected_blocks[joint] = turretring
		if not turretring.joint_connected_blocks.has(block):
			turretring.joint_connected_blocks[joint] = block
	
	return joint

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
	
	# 接触点信息
	if body.get_contact_count() > 0:
		print("  接触点:")
		for i in range(body.get_contact_count()):
			var point = body.get_contact_local_position(i)
			var normal = body.get_contact_local_normal(i)
			print("    %d: 位置%s 法线%s" % [i, point, normal])
