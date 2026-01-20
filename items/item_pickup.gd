class_name Pickup
extends Area2D

@export var attract_speed := 200.0
@export var collect_distance := 16.0

var item_id:String
var amount:int
var target: Cargo = null
var attracting := false
var velocity:Vector2
var bursting := true
var burst_speed := 200
var burst_duration := 1.0
var burst_time := 0.0
var drag := 10

func _ready():
	$Sprite2D.texture = ItemDB.get_item(item_id)["icon"]
	burst()

func _physics_process(delta):
	if bursting:
		burst_time += delta
		global_position += velocity * delta

		# smooth slowdown
		velocity = velocity.move_toward(Vector2.ZERO, drag * burst_speed * delta)

		if burst_time >= burst_duration:
			bursting = false
		return
	
	if attracting and target:
		var dir = (target.global_position - global_position)
		var dist = dir.length()
		
		if dist <= collect_distance:
			target.add_item(item_id, amount)
			queue_free()
			return
		
		global_position += dir.normalized() * attract_speed * clamp(64/dist, 0.2, 1.0) * delta


func burst():
	velocity = Vector2.RIGHT.rotated(randf() * TAU) * burst_speed


func _on_area_entered(area):
	var cargo := area.get_parent() as Cargo
	if not cargo:
		return
	if cargo.can_accept_item(item_id):
		target = cargo
		attracting = true


func _on_area_exited(area):
	var cargo := area.get_parent() as Cargo
	if not cargo:
		return
	if cargo == target:
		target = null
		attracting = false
