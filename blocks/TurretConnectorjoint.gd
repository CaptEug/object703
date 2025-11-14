class_name TurretConnectorJoint
extends PinJoint2D

@export var connection_strength: float = 1.0
@export var lock_rotation: bool = true
@export var maintain_position: bool = true
@export var rotation_stiffness: float = 1.0 
@export var rotation_damping: float = 2.0  

var block: Block
var target_body: RigidBody2D
var initial_global_position: Vector2
var connector: TurretConnector

func _ready():
	setup_joint()

func setup_joint():
	softness = 0.1
	bias = 0.8
	disable_collision = true

func setup(block_node: Block, target: RigidBody2D, connector_ref: TurretConnector):
	block = block_node
	target_body = target
	connector = connector_ref
	
	if maintain_position:
		initial_global_position = block.global_position
	
	node_a = block.get_path()
	node_b = target.get_path()
	
	# 设置连接点在block的本地坐标
	var local_connect_pos = block.to_local(connector.global_position)
	position = local_connect_pos
	
	if lock_rotation:
		# 初始设置一次旋转，后续通过物理力维持
		block.rotation = target.rotation + deg_to_rad(block.base_rotation_degree)
	


func _physics_process(delta):
	if not is_instance_valid(block) or not is_instance_valid(target_body):
		break_connection()
		return
	
	# 应用旋转约束力
	if lock_rotation and is_instance_valid(target_body):
		apply_rotation_constraint(delta)

func apply_rotation_constraint(delta: float):
	# 计算目标旋转角度
	var target_rotation = target_body.global_rotation + deg_to_rad(block.base_rotation_degree)
	
	# 计算当前旋转与目标旋转的差值（归一化到 -PI 到 PI 范围内）
	var rotation_diff = wrapf(target_rotation - block.global_rotation, -PI, PI)
	
	# 如果角度差很小，不需要施加力
	if abs(rotation_diff) < 0.001:
		return
	
	# 计算角速度差
	var target_angular_velocity = target_body.angular_velocity
	var angular_velocity_diff = target_angular_velocity - block.angular_velocity
	
	# 计算恢复扭矩（弹簧力）和阻尼扭矩
	var restoration_torque = rotation_diff * rotation_stiffness * 100000 * block.mass
	var damping_torque = angular_velocity_diff * rotation_damping
	
	# 总扭矩
	var total_torque = restoration_torque + damping_torque
	
	# 应用扭矩到block
	block.apply_torque(total_torque)

func break_connection():
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
	
	var turretring = rigidbody.get_node(node_a_path)  # 使用传入的参数
	if turretring is TurretRing:
		if not block.joint_connected_blocks.has(turretring):
			block.joint_connected_blocks[joint] = rigidbody.get_parent()
		if not turretring.joint_connected_blocks.has(block):
			rigidbody.get_parent().joint_connected_blocks[joint] = block
	
	return joint
