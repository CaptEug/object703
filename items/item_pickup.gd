class_name Pickup
extends Area2D

@export var attract_speed := 600.0
@export var collect_distance := 16.0

var item_id:String
var amount:int
var target: Cargo = null
var attracting := false


func _ready():
	pass # Replace with function body.


func _physics_process(delta):
	if attracting and target:
		var dir = (target.global_position - global_position)
		var dist = dir.length()
		
		if dist <= collect_distance:
			target.add_item(item_id, amount)
			queue_free()
			return
		
		global_position += dir.normalized() * attract_speed * delta



func _on_area_entered(area):
	var cargo := area.get_parent() as Cargo
	if cargo.can_accept_item(item_id):
		target = area
		attracting = true


func _on_area_exited(area):
	if area == target:
		target = null
		attracting = false
