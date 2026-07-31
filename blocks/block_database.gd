extends Node

const INVALID_BLOCK_ID := -1
const CLASS_NATURAL := "natural"
const CLASS_CONSTRUCTED := "constructed"
const HOST_WORLD := "world"
const HOST_VEHICLE := "vehicle"

# Integer block IDs are the compact runtime/save identity. block_name is the
# stable String identity used by developer-authored data.
var blocks := {
	1: {
		"block_name": "Structural Frame",
		"block_class": CLASS_CONSTRUCTED,
		"allowed_hosts": [HOST_WORLD, HOST_VEHICLE],
		"scene_path": "res://blocks/structural/structual_frame.tscn",
		"world_functional": false,
		"size": Vector2i(1, 1),
		"rotatable": false,
		"max_hp": 50.0,
		"mass": 1.0,
		"kinetic_damage_multiplier": 1.0,
		"explosive_damage_multiplier": 1.0,
		"color": Color(0.52, 0.57, 0.61),
		"construction_cost": {
			"metal": 1,
		},
	},
	2: {
		"block_name": "Liquid Container",
		"block_class": CLASS_CONSTRUCTED,
		"allowed_hosts": [HOST_WORLD, HOST_VEHICLE],
		"scene_path": "res://blocks/logistic/liquid_tank.tscn",
		"world_functional": true,
		"size": Vector2i(1, 1),
		"rotatable": true,
		"max_hp": 100.0,
		"mass": 1.0,
		"kinetic_damage_multiplier": 1.0,
		"explosive_damage_multiplier": 1.0,
		"color": Color(0.18, 0.58, 0.72),
		"construction_cost": {},
	},
	3: {
		"block_name": "Cargo Container",
		"block_class": CLASS_CONSTRUCTED,
		"allowed_hosts": [HOST_WORLD, HOST_VEHICLE],
		"scene_path": "res://blocks/logistic/cargo_box.tscn",
		"world_functional": true,
		"size": Vector2i(1, 1),
		"rotatable": true,
		"max_hp": 100.0,
		"mass": 1.0,
		"kinetic_damage_multiplier": 1.0,
		"explosive_damage_multiplier": 1.0,
		"color": Color(0.68, 0.49, 0.25),
		"construction_cost": {},
	},
	4: {
		"block_name": "V2 Engine",
		"block_class": CLASS_CONSTRUCTED,
		"allowed_hosts": [HOST_WORLD, HOST_VEHICLE],
		"scene_path": "res://blocks/mobility/powerpack/v_2.tscn",
		"world_functional": true,
		"size": Vector2i(1, 2),
		"rotatable": true,
		"max_hp": 100.0,
		"mass": 1.0,
		"kinetic_damage_multiplier": 1.0,
		"explosive_damage_multiplier": 1.0,
		"color": Color(0.91, 0.34, 0.12),
		"construction_cost": {},
	},
	5: {
		"block_name": "Metal Track",
		"block_class": CLASS_CONSTRUCTED,
		"allowed_hosts": [HOST_VEHICLE],
		"scene_path": "res://blocks/mobility/track/metal_track.tscn",
		"world_functional": false,
		"size": Vector2i(1, 1),
		"rotatable": true,
		"max_hp": 100.0,
		"mass": 1.0,
		"kinetic_damage_multiplier": 1.0,
		"explosive_damage_multiplier": 1.0,
		"color": Color(0.28, 0.31, 0.34),
		"construction_cost": {},
	},
	6: {
		"block_name": "8.8 cm KwK 43 L/71",
		"block_class": CLASS_CONSTRUCTED,
		"allowed_hosts": [HOST_WORLD, HOST_VEHICLE],
		"scene_path": "res://blocks/weapon/KwK_43.tscn",
		"world_functional": true,
		"size": Vector2i(1, 8),
		"rotatable": true,
		"max_hp": 100.0,
		"mass": 1.0,
		"kinetic_damage_multiplier": 1.0,
		"explosive_damage_multiplier": 1.0,
		"color": Color(0.78, 0.13, 0.10),
		"construction_cost": {},
	},
	7: {
		"block_name": "Dump Container",
		"block_class": CLASS_CONSTRUCTED,
		"allowed_hosts": [HOST_WORLD, HOST_VEHICLE],
		"scene_path": "res://blocks/logistic/dump_container.tscn",
		"world_functional": true,
		"size": Vector2i(1, 1),
		"rotatable": true,
		"max_hp": 100.0,
		"mass": 1.0,
		"kinetic_damage_multiplier": 1.0,
		"explosive_damage_multiplier": 1.0,
		"color": Color(0.50, 0.34, 0.20),
		"construction_cost": {},
	},
	8: {
		"block_name": "Manual Cockpit",
		"block_class": CLASS_CONSTRUCTED,
		"allowed_hosts": [HOST_VEHICLE],
		"scene_path": "res://blocks/control/manual_cockpit.tscn",
		"world_functional": false,
		"size": Vector2i(1, 1),
		"rotatable": true,
		"max_hp": 100.0,
		"mass": 1.0,
		"kinetic_damage_multiplier": 1.0,
		"explosive_damage_multiplier": 1.0,
		"color": Color(1.0, 0.67, 0.12),
		"construction_cost": {},
	},
	9: {
		"block_name": "Sandstone",
		"block_class": CLASS_NATURAL,
		"allowed_hosts": [HOST_WORLD],
		"scene_path": "res://blocks/natural/sandstone.tscn",
		"world_functional": false,
		"size": Vector2i(1, 1),
		"rotatable": false,
		"max_hp": 400.0,
		"mass": 100.0,
		"kinetic_damage_multiplier": 1.0,
		"explosive_damage_multiplier": 1.0,
		"mining_yield": "sandstone",
		"color": Color(0.361, 0.137, 0.114),
		"particle_path": "res://assets/particles/sandstone_shard.tscn",
		"construction_cost": {},
	},
	10: {
		"block_name": "Hematite",
		"block_class": CLASS_NATURAL,
		"allowed_hosts": [HOST_WORLD],
		"scene_path": "res://blocks/natural/hematite.tscn",
		"world_functional": false,
		"size": Vector2i(1, 1),
		"rotatable": false,
		"max_hp": 800.0,
		"mass": 100.0,
		"kinetic_damage_multiplier": 1.0,
		"explosive_damage_multiplier": 0.5,
		"mining_yield": "hematite",
		"color": Color.LIGHT_STEEL_BLUE,
		"particle_path": "res://assets/particles/sandstone_shard.tscn",
		"construction_cost": {},
	},
	11: {
		"block_name": "Crude Oil",
		"phase": "liquid",
		"mass": 1000.0,
		"mining_yield": "crude_oil",
		"color": Color(0.149, 0.078, 0.310),
	},
	12: {
		"block_name": "Sandstone Ground",
		"phase": "ground",
		"color": Color(0.533, 0.251, 0.176),
	},
	13: {
		"block_name": "Drill",
		"block_class": CLASS_CONSTRUCTED,
		"allowed_hosts": [HOST_VEHICLE],
		"scene_path": "res://blocks/industrial/drill.tscn",
		"world_functional": false,
		"size": Vector2i(2, 3),
		"rotatable": true,
		"max_hp": 100.0,
		"mass": 1.0,
		"kinetic_damage_multiplier": 1.0,
		"explosive_damage_multiplier": 1.0,
		"color": Color(0.78, 0.58, 0.16),
		"construction_cost": {},
	},
}


func get_block(block_id: int) -> Dictionary:
	return blocks.get(block_id, {})


func get_block_by_name(block_name: String) -> Dictionary:
	return get_block(get_id_for_name(block_name))


func has_block(block_id: int) -> bool:
	return blocks.has(block_id)


func get_scene(block_id: int) -> PackedScene:
	var scene_path := str(get_block(block_id).get("scene_path", ""))
	if scene_path.is_empty():
		return null
	return load(scene_path) as PackedScene


func get_block_name(block_id: int) -> String:
	return str(get_block(block_id).get("block_name", "unknown_block"))


func get_color(block_id: int) -> Color:
	return get_block(block_id).get("color", Color.MAGENTA)


func get_id_for_scene(scene_path: String) -> int:
	for block_id: int in blocks:
		if blocks[block_id].get("scene_path", "") == scene_path:
			return block_id
	return INVALID_BLOCK_ID


func get_id_for_name(block_name: String) -> int:
	for block_id: int in blocks:
		var definition: Dictionary = blocks[block_id]
		if definition.get("block_name", "") == block_name:
			return block_id
	return INVALID_BLOCK_ID


func get_construction_cost(block_id: int) -> Dictionary:
	return get_block(block_id).get("construction_cost", {}).duplicate(true)


func get_construction_cost_for_scene(scene_path: String) -> Dictionary:
	return get_construction_cost(get_id_for_scene(scene_path))


func get_mining_yield(block_id: int) -> String:
	return str(get_block(block_id).get("mining_yield", ""))


func can_place_on(block_id: int, host_name: String) -> bool:
	return get_block(block_id).get("allowed_hosts", []).has(host_name)


func is_constructed(block_id: int) -> bool:
	return get_block(block_id).get("block_class", "") == CLASS_CONSTRUCTED


func is_world_functional(block_id: int) -> bool:
	return bool(get_block(block_id).get("world_functional", false))


func is_liquid(block_id: int) -> bool:
	return get_block(block_id).get("phase", "") == "liquid"


func is_ground(block_id: int) -> bool:
	return get_block(block_id).get("phase", "") == "ground"


func get_default_liquid_mass(block_id: int) -> float:
	if not is_liquid(block_id):
		return 0.0
	return maxf(float(get_block(block_id).get("mass", 0.0)), 0.0)


func is_rotatable(block_id: int) -> bool:
	return bool(get_block(block_id).get("rotatable", false))


func normalize_rotation(block_id: int, rotation_index: int) -> int:
	if not is_rotatable(block_id):
		return 0
	return wrapi(rotation_index, 0, 4)


func get_size(block_id: int) -> Vector2i:
	return get_block(block_id).get("size", Vector2i.ONE)


func get_max_hp(block_id: int) -> float:
	return maxf(float(get_block(block_id).get("max_hp", 0.0)), 0.0)


func get_damage_multiplier(block_id: int, damage_type: StringName) -> float:
	var key := ""
	match String(damage_type).to_upper():
		"KINETIC":
			key = "kinetic_damage_multiplier"
		"EXPLOSIVE":
			key = "explosive_damage_multiplier"
		_:
			return 1.0
	return maxf(float(get_block(block_id).get(key, 1.0)), 0.0)


func get_legacy_world_block_id(tile_id: int) -> int:
	match tile_id:
		1:
			return 9
		2:
			return 10
	return INVALID_BLOCK_ID


func get_legacy_liquid_block_id(tile_id: int) -> int:
	return 11 if tile_id == 3 else INVALID_BLOCK_ID


func get_legacy_ground_block_id(tile_id: int) -> int:
	return 12 if tile_id == 4 else INVALID_BLOCK_ID


func validate_database(tile_set: TileSet = null) -> PackedStringArray:
	var errors := PackedStringArray()
	var names := {}
	for block_id: int in blocks:
		var definition: Dictionary = blocks[block_id]
		var block_name := str(definition.get("block_name", ""))
		if block_name.is_empty():
			errors.append("Block ID %d has no block_name." % block_id)
		elif names.has(block_name):
			errors.append("Duplicate block_name: %s." % block_name)
		else:
			names[block_name] = block_id
		if not definition.get("color", null) is Color:
			errors.append("Block %s has no valid color." % block_name)
		if is_liquid(block_id):
			if get_default_liquid_mass(block_id) <= 0.0:
				errors.append(
					"Liquid block %s has invalid mass." % block_name
				)
			if not BlockVisualSystem.has_block_tile_visual(block_id):
				errors.append(
					"Liquid block %s has no TileSet block_id visual."
					% block_name
				)
			continue
		if is_ground(block_id):
			if not BlockVisualSystem.has_block_tile_visual(block_id):
				errors.append(
					"Ground block %s has no TileSet block_id visual."
					% block_name
				)
			continue
		if float(definition.get("max_hp", 0.0)) <= 0.0:
			errors.append("Block %s has invalid max_hp." % block_name)
		var scene_path := str(definition.get("scene_path", ""))
		if scene_path.is_empty():
			errors.append("Block %s has no scene file." % block_name)
		elif not ResourceLoader.exists(scene_path):
			errors.append("Block %s has missing scene %s." % [
				block_name,
				scene_path,
			])
		if (
			not bool(definition.get("world_functional", false))
			and definition.get("allowed_hosts", []).has(HOST_WORLD)
			and not BlockVisualSystem.has_block_tile_visual(block_id)
		):
			errors.append(
				"Passive world block %s has no TileSet block_id visual."
				% block_name
			)
	return errors
