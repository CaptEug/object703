extends TurretRing

@onready var armor_block = $Turret/Armor
@onready var d25 = $Turret/D52t
@onready var turret_rigidbody = $Turret

const HITPOINT:float = 1600
const WEIGHT:float = 2000
const BLOCK_NAME:String = 'TurretRing1800mm'
const SIZE:= Vector2(3, 3)
const MAX_TORQUE:float = 1000
const DAMPING:float = 100
const COST:= [{"metal": 10}]

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE

func _ready():
	super._ready()
	await get_tree().process_frame
	setup_connectors()
	await armor_block.connect_aready()
	d25.connect_aready()
	print(turret_grid)

func setup_connectors():
	# 设置碰撞层
	collision_layer = 1  # RigidBody在层3
	if armor_block:
		armor_block.collision_layer = 2  # Block在层2
		# 自动连接所有重叠的连接器
		connect_all_connectors()

func connect_all_connectors():
	if armor_block and turret_rigidbody:
		var armor_connectors = armor_block.get_rigidbody_connectors()
		var turret_connectors = get_rigidbody_connectors_on_node(turret_rigidbody)
		
		for armor_connector in armor_connectors:
			for turret_connector in turret_connectors:
				if armor_connector.global_position.distance_to(turret_connector.global_position) <= armor_connector.connection_range:
					armor_connector.try_connect(turret_connector)

func get_rigidbody_connectors_on_node(node: Node) -> Array[RigidBodyConnector]:
	var connectors: Array[RigidBodyConnector] = []
	var children = node.find_children("*", "RigidBodyConnector", true, false)
	for child in children:
		connectors.append(child as RigidBodyConnector)
	return connectors

#func _process(delta: float) -> void:
	## 调试信息
	#if armor_block:
		#print("Armor connected to RigidBody: ", armor_block.is_attached_to_rigidbody())
