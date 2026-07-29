extends Node

const EMPTY_TILE_ID := 0
const INVALID_TILE_ID := -1

var tiles := {
	1: {
		"name": "sandstone",
		"layer": "wall",
		"phase": "solid",
		"hp": 400,
		"kinetic_aborb": 1.0,
		"explosive_absorb": 1.0,
		"mined_item_id": "sandstone",
		"color": Color(0.361, 0.137, 0.114),
		"particle_path": (
			"res://assets/particles/sandstone_shard.tscn"
		),
	},
	2: {
		"name": "hematite",
		"layer": "wall",
		"phase": "solid",
		"hp": 800,
		"kinetic_aborb": 1.0,
		"explosive_absorb": 0.5,
		"mined_item_id": "hematite",
		"color": Color.LIGHT_STEEL_BLUE,
		"particle_path": (
			"res://assets/particles/sandstone_shard.tscn"
		),
	},
	3: {
		"name": "crude_oil",
		"layer": "wall",
		"phase": "liquid",
		"mass": 1000,
		"color": Color(0.149, 0.078, 0.310),
	},
	4: {
		"name": "sandstone_g",
		"layer": "ground",
		"color": Color(0.533, 0.251, 0.176),
	},
	5: {
		"name": "building",
		"layer": "building",
		"color": Color.YELLOW,
	},
}


func get_tile(tile_id: int) -> Dictionary:
	return tiles.get(tile_id, {})


func get_tile_by_name(tile_name: String) -> Dictionary:
	return get_tile(get_id_by_name(tile_name))


func get_id_by_name(tile_name: String) -> int:
	for tile_id: int in tiles:
		if tiles[tile_id]["name"] == tile_name:
			return tile_id
	return INVALID_TILE_ID


func has_tile(tile_id: int) -> bool:
	return tiles.has(tile_id)


func validate_better_terrain(tile_set: TileSet) -> PackedStringArray:
	var errors := PackedStringArray()
	if tile_set == null:
		errors.append("The map has no TileSet.")
		return errors
	var terrain_count := BetterTerrain.terrain_count(tile_set)
	for tile_id: int in tiles:
		var layer := str(tiles[tile_id].get("layer", ""))
		if layer != "wall":
			continue
		if tile_id >= terrain_count:
			errors.append(
				"Tile ID %d (%s) has no matching BetterTerrain ID."
				% [tile_id, tiles[tile_id]["name"]]
			)
	var reported_ids := {}
	for source_index in tile_set.get_source_count():
		var source := tile_set.get_source(source_index)
		if not source is TileSetAtlasSource:
			continue
		var atlas_source := source as TileSetAtlasSource
		for tile_index in atlas_source.get_tiles_count():
			var coordinates := atlas_source.get_tile_id(tile_index)
			var tile_data: TileData = atlas_source.get_tile_data(
				coordinates,
				0
			)
			if tile_data == null:
				continue
			var tile_id := int(tile_data.get_custom_data("tile_id"))
			if tile_id == EMPTY_TILE_ID:
				continue
			if not has_tile(tile_id):
				if not reported_ids.has(tile_id):
					errors.append(
						"TileSet uses unknown TileDB ID %d." % tile_id
					)
					reported_ids[tile_id] = true
				continue
			if tiles[tile_id].get("layer", "") != "wall":
				continue
			var terrain_id := BetterTerrain.get_tile_terrain_type(
				tile_data
			)
			if terrain_id != tile_id and not reported_ids.has(tile_id):
				errors.append(
					(
						"TileDB ID %d (%s) uses BetterTerrain ID %d."
						% [tile_id, tiles[tile_id]["name"], terrain_id]
					)
				)
				reported_ids[tile_id] = true
	return errors
