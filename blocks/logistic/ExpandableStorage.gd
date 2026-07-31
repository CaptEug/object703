class_name ExpandableStorage
extends Block

var _source_atlas: Texture2D
var _atlas_origin := Vector2i.ZERO
var _visual_root: Node2D


func has_information_panel() -> bool:
	return true


func _ready() -> void:
	super()
	if collision != null and collision.shape != null:
		collision.shape = collision.shape.duplicate()
	_prepare_expandable_visual()
	_resize_container_collision()


func get_container_merge_key() -> String:
	return scene_file_path


func can_merge_storage_members(_members: Array) -> bool:
	return true


func configure_blueprint_size(new_size: Vector2i) -> bool:
	if new_size.x <= 0 or new_size.y <= 0:
		return false
	var unit_count := new_size.x * new_size.y
	size = new_size
	mass *= unit_count
	max_hp *= unit_count
	_scale_storage_capacity(unit_count)
	return true


func merge_container_members(
	members: Array,
	new_origin: Vector2i,
	new_size: Vector2i,
	new_rotation: int
) -> void:
	var combined_mass := 0.0
	var combined_max_hp := 0.0
	var combined_hp := 0.0
	for value: Variant in members:
		var member := value as ExpandableStorage
		if member == null:
			continue
		combined_mass += member.mass
		combined_max_hp += member.max_hp
		combined_hp += member.hp

	_merge_storage_members(members)
	mass = combined_mass
	max_hp = combined_max_hp
	hp = minf(combined_hp, max_hp)
	size = new_size
	rotation_index = wrapi(new_rotation, 0, 4)
	build_local_cells()
	build_default_edge_sockets()
	update_transform(vehicle, new_origin, rotation_index)
	_resize_container_collision()
	refresh_container_visual()
	health_changed.emit()


func refresh_container_visual() -> void:
	if _source_atlas == null:
		return
	if _visual_root == null or not is_instance_valid(_visual_root):
		_visual_root = get_node_or_null("ExpandableVisual") as Node2D
		if _visual_root == null:
			_visual_root = Node2D.new()
			_visual_root.name = "ExpandableVisual"
			add_child(_visual_root)
	BlockVisualSystem.apply_rectangle_merge_to_node(
		_visual_root,
		_source_atlas,
		_atlas_origin,
		size,
		TILE_SIZE
	)


func _prepare_expandable_visual() -> void:
	var original_sprite := get_node_or_null("Sprite2D") as Sprite2D
	if original_sprite == null:
		return
	var atlas_texture := original_sprite.texture as AtlasTexture
	if atlas_texture == null:
		return
	_source_atlas = atlas_texture.atlas
	_atlas_origin = Vector2i(atlas_texture.region.position)
	original_sprite.hide()
	refresh_container_visual()


func _resize_container_collision() -> void:
	if collision == null:
		return
	var rectangle := collision.shape as RectangleShape2D
	if rectangle == null:
		return
	rectangle.size = Vector2(size) * TILE_SIZE
	if collision.get_parent() == self:
		collision.position = Vector2.ZERO
		collision.rotation = 0.0
	elif vehicle != null and collision.get_parent() == vehicle:
		collision.position = position
		collision.rotation = rotation


func _scale_storage_capacity(_unit_count: int) -> void:
	pass


func _merge_storage_members(_members: Array) -> void:
	pass
