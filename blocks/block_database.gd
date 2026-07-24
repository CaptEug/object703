extends Node

var blocks := {
	1: {
		"path": "res://blocks/structural/structual_frame.tscn",
	},
	2: {
		"path": "res://blocks/logistic/fuel_tank.tscn",
	},
	3: {
		"path": "res://blocks/logistic/ammorack.tscn",
	},
	4: {
		"path": "res://blocks/mobility/powerpack/v_2.tscn",
	},
	5: {
		"path": "res://blocks/mobility/track/metal_track.tscn",
	},
	6: {
		"path": "res://blocks/weapon/KwK_43.tscn",
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


func get_id_for_scene(scene_path: String) -> int:
	for block_id in blocks:
		if blocks[block_id]["path"] == scene_path:
			return block_id
	return -1
