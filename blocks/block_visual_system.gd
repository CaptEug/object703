class_name BlockVisualSystem
extends RefCounted

const SHARED_TILE_SET := preload("res://assets/resources/tiles.tres")
const BLOCK_ID_FIELD := "block_id"
const NEIGHBOR_DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i(1, -1),
	Vector2i.RIGHT,
	Vector2i(1, 1),
	Vector2i.DOWN,
	Vector2i(-1, 1),
	Vector2i.LEFT,
	Vector2i(-1, -1),
]
const DIAGONAL_REQUIREMENTS := {
	1: [0, 2],
	3: [2, 4],
	5: [4, 6],
	7: [6, 0],
}

static var _profile_cache: Dictionary = {}
static var _variant_cache: Dictionary = {}


static func resolve_variant(
	host: Object,
	cell: Vector2i,
	block_id: int,
	rotation_index: int
) -> Dictionary:
	return _resolve_block_variant(host, cell, block_id, rotation_index)


static func has_block_tile_visual(block_id: int) -> bool:
	return not _get_profile(block_id).is_empty()


static func block_uses_merge_mask(block_id: int) -> bool:
	return bool(
		_get_profile(block_id).get(
			"uses_merge_mask",
			false
		)
	)


static func get_block_merge_group(block_id: int) -> String:
	return str(
		_get_profile(block_id).get(
			"merge_group",
			""
		)
	)


static func _resolve_block_variant(
	host: Object,
	cell: Vector2i,
	block_id: int,
	rotation_index: int
) -> Dictionary:
	var profile := _get_profile(block_id)
	if profile.is_empty():
		return {}
	if not bool(profile.get("uses_merge_mask", false)):
		return _copy_variant(profile.get("default", {}))

	var mask := _normalize_blob_mask(
		_get_merge_mask(
			host,
			cell,
			profile,
			rotation_index
		)
	)
	var selected := _get_mask_variant(
		int(profile["source_id"]),
		block_id,
		mask
	)
	if selected.is_empty():
		selected = profile.get("default", {})
	return _copy_variant(selected)


static func _get_merge_mask(
	host: Object,
	cell: Vector2i,
	profile: Dictionary,
	rotation_index: int
) -> int:
	if (
		host == null
		or not host.has_method("get_visual_merge_data_at")
	):
		return 0
	var group := str(profile.get("merge_group", ""))
	if group.is_empty():
		return 0

	var mask := 0
	for index in NEIGHBOR_DIRECTIONS.size():
		var neighbor_data: Dictionary = host.call(
			"get_visual_merge_data_at",
			cell + NEIGHBOR_DIRECTIONS[index]
		)
		if str(neighbor_data.get("group", "")) != group:
			continue
		if (
			bool(profile.get("rotation_sensitive", false))
			and int(neighbor_data.get("rotation", 0))
			!= rotation_index
		):
			continue
		mask |= 1 << index
	return mask


static func _normalize_blob_mask(mask: int) -> int:
	var normalized := mask
	for diagonal_index: int in DIAGONAL_REQUIREMENTS:
		var requirements: Array = DIAGONAL_REQUIREMENTS[diagonal_index]
		var first_bit := 1 << int(requirements[0])
		var second_bit := 1 << int(requirements[1])
		if (
			(mask & first_bit) == 0
			or (mask & second_bit) == 0
		):
			normalized &= ~(1 << diagonal_index)
	return normalized


static func _get_profile(block_id: int) -> Dictionary:
	if block_id <= 0:
		return {}
	if not _profile_cache.has(block_id):
		_profile_cache[block_id] = _build_profile(block_id)
	return _profile_cache[block_id]


static func _build_profile(block_id: int) -> Dictionary:
	if SHARED_TILE_SET == null:
		return {}
	for source_index in SHARED_TILE_SET.get_source_count():
		var source_id := SHARED_TILE_SET.get_source_id(source_index)
		var source := SHARED_TILE_SET.get_source(
			source_id
		) as TileSetAtlasSource
		if source == null:
			continue
		var result := {}
		for tile_index in source.get_tiles_count():
			var atlas_coordinates := source.get_tile_id(tile_index)
			for alternative_index in source.get_alternative_tiles_count(
				atlas_coordinates
			):
				var alternative := source.get_alternative_tile_id(
					atlas_coordinates,
					alternative_index
				)
				var tile_data := source.get_tile_data(
					atlas_coordinates,
					alternative
				)
				if (
					tile_data == null
					or int(tile_data.get_custom_data(BLOCK_ID_FIELD))
					!= block_id
				):
					continue
				var variant := {
					"source_id": source_id,
					"atlas_coordinates": atlas_coordinates,
					"alternative": alternative,
				}
				if result.is_empty():
					result = {
						"source_id": source_id,
						"merge_group": str(
							source.get_meta(
								"visual_merge_group",
								"source:%d" % source_id
							)
						),
						"rotation_sensitive": bool(
							source.get_meta(
								"visual_rotation_sensitive",
								false
							)
						),
						"uses_merge_mask": false,
						"default": variant,
					}
				if tile_data.has_meta("connectivity_mask"):
					result["uses_merge_mask"] = true
					if int(
						tile_data.get_meta("connectivity_mask")
					) == 0:
						result["default"] = variant
		if not result.is_empty():
			return result
	return {}


static func _get_mask_variant(
	source_id: int,
	block_id: int,
	mask: int
) -> Dictionary:
	var cache_key := "%d:%d" % [
		source_id,
		block_id,
	]
	if not _variant_cache.has(cache_key):
		_variant_cache[cache_key] = _build_mask_variants(
			source_id,
			block_id
		)
	var variants: Dictionary = _variant_cache[cache_key]
	return variants.get(mask, {})


static func _build_mask_variants(
	source_id: int,
	block_id: int
) -> Dictionary:
	var result := {}
	if (
		SHARED_TILE_SET == null
		or not SHARED_TILE_SET.has_source(source_id)
	):
		return result
	var source := SHARED_TILE_SET.get_source(
		source_id
	) as TileSetAtlasSource
	if source == null:
		return result
	for tile_index in source.get_tiles_count():
		var atlas_coordinates := source.get_tile_id(tile_index)
		for alternative_index in source.get_alternative_tiles_count(
			atlas_coordinates
		):
			var alternative := source.get_alternative_tile_id(
				atlas_coordinates,
				alternative_index
			)
			var tile_data := source.get_tile_data(
				atlas_coordinates,
				alternative
			)
			if (
				tile_data == null
				or int(tile_data.get_custom_data(BLOCK_ID_FIELD))
				!= block_id
				or not tile_data.has_meta("connectivity_mask")
			):
				continue
			result[int(tile_data.get_meta("connectivity_mask"))] = {
				"source_id": source_id,
				"atlas_coordinates": atlas_coordinates,
				"alternative": alternative,
			}
	return result


static func apply_variant_to_sprite(
	sprite: Sprite2D,
	variant: Dictionary,
	tile_set: TileSet = SHARED_TILE_SET
) -> bool:
	if sprite == null or variant.is_empty() or tile_set == null:
		return false
	var source_id := int(variant.get("source_id", -1))
	if not tile_set.has_source(source_id):
		return false
	var source := tile_set.get_source(source_id) as TileSetAtlasSource
	if source == null:
		return false
	var atlas_coordinates: Vector2i = variant.get(
		"atlas_coordinates",
		Vector2i(-1, -1)
	)
	if not source.has_tile(atlas_coordinates):
		return false
	var alternative := int(variant.get("alternative", 0))
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = source.texture
	atlas_texture.region = source.get_tile_texture_region(
		atlas_coordinates,
		alternative
	)
	sprite.texture = atlas_texture
	sprite.flip_h = bool(variant.get("flip_h", false))
	sprite.flip_v = bool(variant.get("flip_v", false))
	return true


static func _copy_variant(value: Dictionary) -> Dictionary:
	if value.is_empty():
		return {}
	return {
		"source_id": int(value.get("source_id", -1)),
		"atlas_coordinates": value.get(
			"atlas_coordinates",
			Vector2i(-1, -1)
		),
		"alternative": int(value.get("alternative", 0)),
		"flip_h": bool(value.get("flip_h", false)),
		"flip_v": bool(value.get("flip_v", false)),
	}
