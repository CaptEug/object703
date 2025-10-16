class_name BlockPinJoint2D
extends PinJoint2D

@export var connection_strength: float = 1.0
@export var lock_rotation: bool = true
@export var maintain_position: bool = true

var block: Block
var target_body: RigidBody2D
var initial_global_position: Vector2
var connector: RigidBodyConnector

func _ready():
	print("BlockPinJoint2D 创建")
	setup_joint()

func setup_joint():
	softness = 0.1
	bias = 0.8
	disable_collision = true
	print("关节参数设置完成")

func setup(block_node: Block, target: RigidBody2D, connector_ref: RigidBodyConnector):
	print("设置关节连接")
	block = block_node
	target_body = target
	connector = connector_ref
	
	if maintain_position:
		initial_global_position = block.global_position
		print("初始位置记录: ", initial_global_position)
	
	node_a = block.get_path()
	node_b = target.get_path()
	
	# 设置连接点在block的本地坐标
	var local_connect_pos = block.to_local(connector.global_position)
	position = local_connect_pos
	print("连接点位置: ", position)
	
	if lock_rotation:
		block.rotation = target.rotation
		print("旋转锁定启用")
	
	print("关节设置完成: ", block.name, " <-> ", target.name)

func _physics_process(delta):
	if not is_instance_valid(block) or not is_instance_valid(target_body):
		print("关节目标失效，断开连接")
		break_connection()
		return
	
	if maintain_position:
		maintain_block_position()
	
	if lock_rotation and is_instance_valid(target_body):
		block.global_rotation = target_body.global_rotation

func maintain_block_position():
	var position_diff = initial_global_position - block.global_position
	if position_diff.length() > 1.0:
		var correction_force = position_diff * 100.0 * connection_strength
		block.apply_central_force(correction_force)

func break_connection():
	print("断开关节连接")
	if block and block.joint_connected_blocks.has(self):
		block.joint_connected_blocks.erase(self)
		print("从Block连接列表中移除")
	
	if connector and is_instance_valid(connector):
		connector.disconnect_connection()
		print("通知连接器断开")
	
	queue_free()
	print("关节已销毁")

static func connect_to_rigidbody(block: Block, rigidbody: RigidBody2D, connector_ref: RigidBodyConnector, lock_rot: bool = true, maintain_pos: bool = true) -> BlockPinJoint2D:
	print("创建BlockPinJoint2D连接")
	var joint = BlockPinJoint2D.new()
	joint.lock_rotation = lock_rot
	joint.maintain_position = maintain_pos
	joint.setup(block, rigidbody, connector_ref)
	block.add_child(joint)
	block.joint_connected_blocks[joint] = rigidbody
	print("关节已添加到Block")
	return joint
