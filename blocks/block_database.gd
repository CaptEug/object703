extends Node

var blocks := {
	1: {
		"block_name": "Structual Frame",
		"path": "res://blocks/structural/structual_frame.tscn",
		"construction_cost": {
			"metal": 1,
		},
	},
	2: {
		"block_name": "Liquid Tank",
		"path": "res://blocks/logistic/liquid_tank.tscn",
		"construction_cost": {
			"metal": 1,
			"metal_parts": 1,
		},
	},
	3: {
		"block_name": "Cargo Box",
		"path": "res://blocks/logistic/cargo_box.tscn",
		"construction_cost": {
			"metal": 1,
			"metal_parts": 1,
		},
	},
	4: {
		"block_name": "V2",
		"path": "res://blocks/mobility/powerpack/v_2.tscn",
		"construction_cost": {
			"metal": 2,
			"metal_parts": 2,
		},
	},
	5: {
		"block_name": "Metal Track",
		"path": "res://blocks/mobility/track/metal_track.tscn",
		"construction_cost": {
			"metal": 1,
			"metal_parts": 1,
		},
	},
	6: {
		"block_name": "8.8cm KwK 43 L/71",
		"path": "res://blocks/weapon/KwK_43.tscn",
		"construction_cost": {
			"metal": 2,
			"metal_parts": 2,
		},
	},
	7: {
		"block_name": "Dump Container",
		"path": "res://blocks/logistic/dump_container.tscn",
		"construction_cost": {
			"metal": 1,
		},
	},
	8: {
		"block_name": "Manual Cockpit",
		"path": "res://blocks/control/manual_cockpit.tscn",
		"construction_cost": {
			"metal": 1,
			"metal_parts": 1,
		},
	},
}


func get_block(block_id: int) -> Dictionary:
	if blocks.has(block_id):
		return blocks[block_id]
	return {}


func has_block(block_id: int) -> bool:
	return blocks.has(block_id)


func get_scene(block_id: int) -> PackedScene:
	var block_data := get_block(block_id)
	if block_data.is_empty():
		return null
	return load(block_data["path"]) as PackedScene


func get_block_name(block_id: int) -> String:
	return str(get_block(block_id).get("block_name", "Unknown Block"))


func get_id_for_scene(scene_path: String) -> int:
	for block_id in blocks:
		if blocks[block_id]["path"] == scene_path:
			return block_id
	return -1


func get_id_for_name(block_name: String) -> int:
	for block_id in blocks:
		if blocks[block_id]["block_name"] == block_name:
			return block_id
	return -1


func get_construction_cost(block_id: int) -> Dictionary:
	var block_data := get_block(block_id)
	return block_data.get("construction_cost", {}).duplicate(true)


func get_construction_cost_for_scene(scene_path: String) -> Dictionary:
	return get_construction_cost(get_id_for_scene(scene_path))
