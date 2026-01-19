extends Block

const HITPOINT:float = 1200
const WEIGHT:float = 1500
const BLOCK_NAME:String = 'drill'
const SIZE:= Vector2(2, 3)
const TYPE:= 'Auxiliary'

var description := ""
var outline_tex := preload("res://assets/outlines/drill_outline.png")
var spark_particle = preload("res://assets/particles/spark.tscn")

var inventory:Array = []
var on:bool
var dmg:= 150
var connected_cargo:Array[Cargo] = []

@onready var drill_sprite:= $Mask/Sprite2D
var sprite_origin:Vector2
var drill_scroll:float = 0.0
var drill_speed:float = 0.0
var max_drill_speed:float = 3

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	type = TYPE


func _ready():
	super._ready()
	sprite_origin = drill_sprite.texture.region.position


func _physics_process(delta):
	update_drill_sprite(delta)
	if not functioning:
		on = false
		return
	find_all_connected_cargo()
	if on:
		damage_contacted_blocks(delta)


func _unhandled_input(event: InputEvent) -> void:
	if get_parent_vehicle() and functioning:
		var control_method = get_parent_vehicle().control.get_method()
		if control_method == "manual_control":
			if event.is_action("FIRE_MAIN"):  # only respond to FIRE_MAIN events
				on = event.is_action_pressed("FIRE_MAIN")  # true on press, false on release


func damage_contacted_blocks(delta):
	for body in $Area2D.get_overlapping_bodies():
		if body is Block:
			if body.parent_vehicle == parent_vehicle:
				continue
			var block_hp = body.current_hp
			if block_hp >= 0:
				var damage_to_deal = min(dmg * delta, block_hp)
				body.damage(damage_to_deal)
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
					if not tilemap.get_celldata(cell):
						continue
					var tile_hp = tilemap.layerdata[cell]["current_hp"]
					#if tile_hp - dmg * delta * 2 <= 0:
						#gain_material(tilemap, cell)
					tilemap.damage_tile(cell, dmg * delta * 2) #deal double dmg to tile


func update_drill_sprite(delta):
	if on:
		drill_speed = clamp(drill_speed + 1 * delta, 0, max_drill_speed)
	else:
		drill_speed = clamp(drill_speed - 1 * delta, 0, max_drill_speed)
	drill_scroll += drill_speed
	var wrapped_x = wrapf(drill_scroll, 0, 32) #drill sprite is 32x32
	drill_sprite.texture.region.position = sprite_origin + Vector2(wrapped_x, 0)


#func gain_material(tilemap:WallLayer, cell:Vector2i):
	#var item = tilemap.layerdata[cell]["matter"]
	#for cargo in connected_cargo:
		#cargo.add_item(item, 1)


func find_all_connected_cargo():
	connected_cargo.clear()
	for block in get_all_connected_blocks():
		if block is Cargo:
			connected_cargo.append(block)
	return connected_cargo
