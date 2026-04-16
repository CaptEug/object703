class_name Projectile
extends RigidBody2D

enum ShellType {AP, HE, APHE}
@export var shell_type : ShellType
@export var weight : float = 1.0
@export var max_K_DMG : float = 0.0   # max kinetic damage
var remaining_K_DMG : float
@export var max_E_DMG : float = 100   # max explosive damage
@export var explosion_radius : int = 3   # in tile
@export var max_range : int   # in tile
@export var ricochet_angle: float = 70.0

@onready var shell_body : Area2D = $Area2D
var vehicle : Vehicle
var distance_travelled : float = 0.0
var ricochet_loss : float = 0.5
var last_pos : Vector2

var explosion_scene := load("res://items/shells/explosion.tscn")


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	mass = weight
	last_pos = global_position
	remaining_K_DMG = max_K_DMG
	shell_body.collision_mask = 3
	shell_body.body_entered.connect(_on_shell_body_entered)


func _physics_process(_delta: float) -> void:
	var from := last_pos
	var to := global_position
	
	var step_distance := from.distance_to(to)
	distance_travelled += step_distance
	var max_distance := max_range * Globals.TILE_SIZE
	
	#remaining_K_DMG -= max_K_DMG * (step_distance / max_distance)
	
	if distance_travelled > max_distance:
		queue_free()
		return
	
	last_pos = global_position

# =========================
# HIT HANDLING
# =========================



# =========================
# SHELL FUNCTIONS
# =========================

func ricochet(normal: Vector2) -> void:
	print("Ricochet!")
	linear_velocity = linear_velocity.bounce(normal) * ricochet_loss
	remaining_K_DMG *= ricochet_loss
	
	# update rotation to match new direction
	rotation = linear_velocity.angle() + PI/2
	
	# push out of surface
	#global_position = hit_pos + normal * 2.0


func explode() -> void:
	var explosion := explosion_scene.instantiate() as Explosion
	explosion.global_position = global_position
	explosion.radius = explosion_radius
	explosion.max_damage = max_E_DMG
	get_tree().current_scene.add_child(explosion)


# =========================
# DAMAGE / EFFECT
# =========================

func _on_shell_body_entered(body: CollisionObject2D) -> void:
	# hit vehicle
	if body is Vehicle:
		var vehicle_target := body as Vehicle
		var hit_cell := vehicle_target.world_to_cell(global_position)
		print(hit_cell)
		var hit_block := vehicle_target.get_block(hit_cell)
		
		if hit_block == null:
			return
		
		match shell_type:
			
			ShellType.AP:
				var block_hp := hit_block.hp
				var damage_dealt = min(block_hp, remaining_K_DMG)
				hit_block.damage(damage_dealt, "KINETIC")
				remaining_K_DMG -= damage_dealt
				print(remaining_K_DMG)
				if remaining_K_DMG <= 0.0:
					queue_free()
					return
			
			ShellType.HE:
				explode()
				queue_free()
				return
			
			ShellType.APHE:
				var block_hp := hit_block.hp
				var damage_dealt = min(block_hp, remaining_K_DMG)
				hit_block.damage(damage_dealt, "KINETIC")
				remaining_K_DMG -= damage_dealt
				print(remaining_K_DMG)
				if remaining_K_DMG <= 0.0:
					explode()
					queue_free()
					return
