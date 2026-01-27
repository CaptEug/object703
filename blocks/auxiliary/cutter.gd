extends Block

const HITPOINT:float = 800
const WEIGHT:float = 1000
const BLOCK_NAME:String = 'cutter'
const SIZE:= Vector2(2, 2)
const TYPE:= 'Auxiliary'

var description := "saw use to cut metal"
var outline_tex := preload("res://assets/outlines/cutter_outline.png")
var spark_particle = preload("res://assets/particles/spark.tscn")

var inventory:Array = []
var on:bool
var dmg:= 150
var connected_cargos:Array[Cargo] = []
@onready var saw:RigidBody2D = $Saw

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	type = TYPE


func _physics_process(delta):
	if not functioning:
		on = false
		return
	find_all_connected_cargo()
	if on:
		saw.apply_torque(1000)
		damage_contacted_blocks(delta)


func _unhandled_input(event: InputEvent) -> void:
	if get_parent_vehicle() and functioning:
		var control_method = get_parent_vehicle().control.get_method()
		if control_method == "manual_control":
			if event.is_action("FIRE_MAIN"):  # only respond to FIRE_MAIN events
				on = event.is_action_pressed("FIRE_MAIN")  # true on press, false on release


func damage_contacted_blocks(delta):
	for body in $Saw/Area2D.get_overlapping_bodies():
		if body is Block:
			if body.parent_vehicle == parent_vehicle:
				continue
			var block_hp = body.current_hp
			if block_hp >= 0:
				var damage_to_deal = min(dmg * delta * 2, block_hp) #deal double dmg to block
				body.damage(damage_to_deal, self)
			# spark particle
			if randf_range(0, 1) < 0.1:
				var spark_pos = (global_position + body.global_position)/2
				var spark_rot = (global_position - body.global_position).rotated(-PI/2).angle()
				var spark = spark_particle.instantiate()
				spark.position = spark_pos
				spark.rotation = spark_rot
				spark.emitting = true
				map.add_child(spark)
		
		if body is WallLayer:
			var tilemap = body
			var center_cell = tilemap.local_to_map(global_position)
			var r_tiles = 1
			for y in range(center_cell.y - r_tiles, center_cell.y + r_tiles + 1):
				for x in range(center_cell.x - r_tiles, center_cell.x + r_tiles + 1):
					var cell = Vector2i(x, y)
					var celldata = tilemap.get_celldata(cell)
					if not celldata:
						continue
					if TileDB.get_tile(celldata["matter"])["phase"] != "solid":
						continue
					tilemap.damage_tile(cell, dmg * delta)


func find_all_connected_cargo():
	connected_cargos.clear()
	for block in get_all_connected_blocks():
		if block is Cargo:
			connected_cargos.append(block)
	return connected_cargos
