extends TurretRing

const HITPOINT:float = 1600
const WEIGHT:float = 2000
const BLOCK_NAME:String = 'TurretRing1800mm'
const SIZE:= Vector2(3, 3)
const MAX_TORQUE:float = 1000000
const COST:= [{"metal": 10}]

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	max_torque = MAX_TORQUE

func _ready():
	super._ready()
	await get_tree().process_frame
	setup_connectors()
	print(turret_grid)

func setup_connectors():
	# 设置碰撞层
	collision_layer = 1  # RigidBody在层3
		# 自动连接所有重叠的连接器

func get_rigidbody_connectors_on_node(node: Node) -> Array[TurretConnector]:
	var connectors: Array[TurretConnector] = []
	var children = node.find_children("*", "TurretConnector", true, false)
	for child in children:
		connectors.append(child as TurretConnector)
	return connectors

#func _process(delta: float) -> void:
	## 调试信息
	#if armor_block:
		#print("Armor connected to RigidBody: ", armor_block.is_attached_to_rigidbody())
