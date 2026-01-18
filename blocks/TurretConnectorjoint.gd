class_name TurretConnectorJoint
extends PinJoint2D

@export var connection_strength: float = 1.0
@export var lock_rotation: bool = true
@export var maintain_position: bool = true
@export var rotation_stiffness: float = 1000
@export var rotation_damping: float = 200

var block: Block
var target_body: StaticBody2D
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

func setup(block_node: Block, target: StaticBody2D, connector_ref: TurretConnector):
	block = block_node
	target_body = target
	connector = connector_ref
	
	# 设置节点路径
	node_a = block.get_path()
	node_b = target.get_path()
	
	# 计算连接点在target本地坐标系中的位置
	var global_connect_pos = connector.global_position
	position = target.to_local(global_connect_pos)
	
	# 关键：修正旋转对齐逻辑
	# 不再在setup中立即设置旋转，而是在_physics_process中通过约束慢慢对齐
	# 这样可以避免立即错位
	if lock_rotation:
		# 保存块的初始旋转，用于后续的旋转约束
		# 但不立即设置block.rotation，避免强制对齐导致错位
		pass

func _physics_process(delta):
	if not is_instance_valid(block) or not is_instance_valid(target_body):
		break_connection()
		return
	
	if lock_rotation and is_instance_valid(target_body):
		apply_rotation_constraint(delta)
	
	if not check_connection_strength():
		return

func apply_rotation_constraint(delta: float):
	if not is_instance_valid(block):
		return
		
	# 获取块的物理状态
	var body_rid = block.get_rid()
	if not body_rid.is_valid():
		return
		
	var body_state = PhysicsServer2D.body_get_direct_state(body_rid)
	if body_state == null:
		return
		
	var inverse_inertia = body_state.inverse_inertia
	var actual_inertia = 1.0 / inverse_inertia if inverse_inertia > 0 else 0.0
	
	if actual_inertia <= 0:
		return
	
	# 计算目标旋转：炮塔篮筐旋转 + 块的基础旋转
	var target_rotation = target_body.global_rotation + deg_to_rad(block.base_rotation_degree)
	
	# 计算当前旋转与目标旋转的差值
	var rotation_diff = wrapf(target_rotation - block.global_rotation, -PI, PI)
	
	# 如果旋转差很小，不应用扭矩（添加容忍度）
	if abs(rotation_diff) < deg_to_rad(0.5):  # 0.5度容忍度
		return
	
	var target_angular_velocity = target_body.get_parent().angular_velocity
	var angular_velocity_diff = target_angular_velocity - block.angular_velocity
	
	# 使用更柔和的旋转刚度
	var soft_rotation_stiffness = rotation_stiffness * 0.5  # 降低刚度
	
	var restoration_torque = rotation_diff * soft_rotation_stiffness * actual_inertia
	var damping_torque = angular_velocity_diff * rotation_damping * actual_inertia 
	var total_torque = restoration_torque + damping_torque
	
	# 应用较小的扭矩，避免突然的旋转
	block.apply_torque(total_torque / 20)

func check_connection_strength() -> bool:
	if not maintain_position or initial_distance <= 0:
		return true
	
	var current_distance = block.global_position.distance_to(target_body.global_position)
	var stretch_ratio = current_distance / initial_distance
	
	if stretch_ratio > (1.0 + connection_strength * 0.5):
		break_connection()
		return false
	
	return true

func break_connection():
	if block and block.joint_connected_blocks.has(self):
		block.joint_connected_blocks.erase(self)
	
	if connector and is_instance_valid(connector):
		connector.disconnect_connection()
	
	queue_free()

# 创建函数 - 需要传入lock_rot参数
static func connect_to_staticbody(block: Block, staticbody: StaticBody2D, connector_ref: TurretConnector, turret_ring: TurretRing, lock_rot: bool = true, maintain_pos: bool = true) -> TurretConnectorJoint:
	var joint = TurretConnectorJoint.new()
	
	# 使用传入的参数设置属性
	joint.lock_rotation = lock_rot  # 关键：使用参数而不是硬编码的true
	joint.maintain_position = maintain_pos
	
	# 设置节点路径
	joint.node_a = block.get_path()
	joint.node_b = staticbody.get_path()
	joint.setup(block, staticbody, connector_ref)
	
	# 最后添加为子节点
	staticbody.add_child(joint)
	
	# 保持原有的连接关系管理
	if turret_ring is TurretRing:
		if not block.joint_connected_blocks.has(turret_ring):
			block.joint_connected_blocks[joint] = turret_ring
		if not turret_ring.joint_connected_blocks.has(block):
			turret_ring.joint_connected_blocks[joint] = block
	
	return joint
