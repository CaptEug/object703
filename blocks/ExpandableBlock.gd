class_name ExpandableBlock
extends Block

var _union_source_atlas: Texture2D
var _union_atlas_origin := Vector2i.ZERO
var _union_visual_root: Node2D


func _ready() -> void:
	super()
	if collision != null and collision.shape != null:
		collision.shape = collision.shape.duplicate()
	_prepare_union_visual()
	_resize_union_collision()
	_on_union_geometry_changed()


func get_union_key() -> String:
	return scene_file_path


func can_union_members(_members: Array) -> bool:
	return true


func configure_union_size(new_size: Vector2i) -> bool:
	if new_size.x <= 0 or new_size.y <= 0:
		return false
	var base_size := (
		BlockDB.get_size(block_id)
		if BlockDB.has_block(block_id)
		else size
	)
	if (
		base_size.x <= 0
		or base_size.y <= 0
		or new_size.x % base_size.x != 0
		or new_size.y % base_size.y != 0
	):
		return false
	var base_area := base_size.x * base_size.y
	var unit_count := new_size.x * new_size.y / base_area
	size = new_size
	mass *= unit_count
	max_hp *= unit_count
	_scale_union_capacity(unit_count)
	_on_union_geometry_changed()
	return true


func merge_union_members(
	members: Array,
	new_origin: Vector2i,
	new_size: Vector2i,
	new_rotation: int
) -> void:
	var current_world_host := block_host
	var combined_mass := 0.0
	var combined_max_hp := 0.0
	var combined_hp := 0.0
	for value: Variant in members:
		var member := value as ExpandableBlock
		if member == null:
			continue
		combined_mass += member.mass
		combined_max_hp += member.max_hp
		combined_hp += member.hp

	_merge_union_data(members)
	mass = combined_mass
	max_hp = combined_max_hp
	hp = minf(combined_hp, max_hp)
	size = new_size
	rotation_index = wrapi(new_rotation, 0, 4)
	build_local_cells()
	build_default_edge_sockets()
	if vehicle == null and current_world_host != null:
		update_world_transform(
			current_world_host,
			new_origin,
			rotation_index
		)
	else:
		update_transform(vehicle, new_origin, rotation_index)
	_resize_union_collision()
	refresh_union_visual()
	_on_union_geometry_changed()
	health_changed.emit()


func refresh_union_visual() -> void:
	if _union_source_atlas == null:
		return
	if (
		_union_visual_root == null
		or not is_instance_valid(_union_visual_root)
	):
		_union_visual_root = get_node_or_null(
			"UnionVisual"
		) as Node2D
		if _union_visual_root == null:
			_union_visual_root = Node2D.new()
			_union_visual_root.name = "UnionVisual"
			add_child(_union_visual_root)
	BlockVisualSystem.apply_rectangle_merge_to_node(
		_union_visual_root,
		_union_source_atlas,
		_union_atlas_origin,
		size,
		TILE_SIZE
	)


func _prepare_union_visual() -> void:
	var original_sprite := get_node_or_null("Sprite2D") as Sprite2D
	if original_sprite == null:
		return
	var atlas_texture := original_sprite.texture as AtlasTexture
	if atlas_texture == null:
		return
	_union_source_atlas = atlas_texture.atlas
	_union_atlas_origin = Vector2i(atlas_texture.region.position)
	original_sprite.hide()
	refresh_union_visual()


func _resize_union_collision() -> void:
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
	elif collision.get_parent() is WorldBlockBody:
		collision.position = Vector2.ZERO
		collision.rotation = 0.0


func _scale_union_capacity(_unit_count: int) -> void:
	pass


func _merge_union_data(_members: Array) -> void:
	pass


func _on_union_geometry_changed() -> void:
	pass


static func find_rectangular_groups(
	members: Array[ExpandableBlock],
	get_neighbor: Callable
) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var unvisited := {}
	for member: ExpandableBlock in members:
		if is_instance_valid(member):
			unvisited[member] = true

	while not unvisited.is_empty():
		var start := unvisited.keys()[0] as ExpandableBlock
		var component := _take_component(
			start,
			unvisited,
			get_neighbor
		)
		if component.size() <= 1:
			continue
		var rectangle := _get_complete_rectangle(component)
		if rectangle.size == Vector2i.ZERO:
			continue
		if not start.can_union_members(component):
			continue
		groups.append({
			"members": component,
			"rectangle": rectangle,
		})
	return groups


static func find_rectangular_group_from(
	start: ExpandableBlock,
	get_neighbor: Callable
) -> Dictionary:
	if not is_instance_valid(start):
		return {}
	var members: Array = []
	var visited := {}
	var stack: Array[ExpandableBlock] = [start]
	var union_key := start.get_union_key()
	var union_rotation := start.rotation_index
	while not stack.is_empty():
		var current: ExpandableBlock = stack.pop_back()
		if visited.has(current):
			continue
		visited[current] = true
		members.append(current)
		for occupied_cell: Vector2i in current.get_occupied_cells():
			for direction: Vector2i in Block.SIDE_DIRS.values():
				var neighbor := get_neighbor.call(
					occupied_cell + direction
				) as ExpandableBlock
				if (
					neighbor != null
					and not visited.has(neighbor)
					and neighbor.get_union_key() == union_key
					and neighbor.rotation_index == union_rotation
				):
					stack.append(neighbor)
	if members.size() <= 1:
		return {}
	var rectangle := _get_complete_rectangle(members)
	if (
		rectangle.size == Vector2i.ZERO
		or not start.can_union_members(members)
	):
		return {}
	return {
		"members": members,
		"rectangle": rectangle,
	}


static func _take_component(
	start: ExpandableBlock,
	unvisited: Dictionary,
	get_neighbor: Callable
) -> Array:
	var result: Array = []
	var queue: Array[ExpandableBlock] = [start]
	var union_key := start.get_union_key()
	var union_rotation := start.rotation_index
	while not queue.is_empty():
		var current := queue.pop_front() as ExpandableBlock
		if not unvisited.has(current):
			continue
		unvisited.erase(current)
		result.append(current)
		for occupied_cell: Vector2i in current.get_occupied_cells():
			for direction: Vector2i in Block.SIDE_DIRS.values():
				var neighbor := get_neighbor.call(
					occupied_cell + direction
				) as ExpandableBlock
				if (
					neighbor != null
					and neighbor != current
					and unvisited.has(neighbor)
					and neighbor.get_union_key() == union_key
					and neighbor.rotation_index == union_rotation
				):
					queue.append(neighbor)
	return result


static func _get_complete_rectangle(component: Array) -> Rect2i:
	var occupied := {}
	var has_cell := false
	var min_cell := Vector2i.ZERO
	var max_cell := Vector2i.ZERO
	for value: Variant in component:
		var member := value as ExpandableBlock
		if member == null:
			continue
		for cell: Vector2i in member.get_occupied_cells():
			occupied[cell] = true
			if not has_cell:
				min_cell = cell
				max_cell = cell
				has_cell = true
			else:
				min_cell.x = mini(min_cell.x, cell.x)
				min_cell.y = mini(min_cell.y, cell.y)
				max_cell.x = maxi(max_cell.x, cell.x)
				max_cell.y = maxi(max_cell.y, cell.y)
	if not has_cell:
		return Rect2i()
	var rectangle_size := max_cell - min_cell + Vector2i.ONE
	if occupied.size() != rectangle_size.x * rectangle_size.y:
		return Rect2i()
	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			if not occupied.has(Vector2i(x, y)):
				return Rect2i()
	return Rect2i(min_cell, rectangle_size)
