extends Node

const INVALID_ITEM_ID := -1

enum ItemType {
	MINERAL,
	MATERIAL,
	LIQUID,
}

enum ItemSubclass {
	RAW_ORE,
	AMMO,
	FUEL,
}

var items := {
	1: {
		"name": "scrap",
		"type": ItemType.MATERIAL,
		"subclasses": [],
		"weight": 100.0,
		"icon": preload("res://assets/icons/items/scrap.png"),
	},
	2: {
		"name": "metal",
		"type": ItemType.MATERIAL,
		"subclasses": [],
		"weight": 100.0,
		"icon": preload("res://assets/icons/items/metal.png"),
	},
	3: {
		"name": "metal_parts",
		"type": ItemType.MATERIAL,
		"subclasses": [],
		"weight": 25.0,
		"icon": preload("res://assets/icons/items/metal.png"),
	},
	4: {
		"name": "sandstone",
		"type": ItemType.MINERAL,
		"subclasses": [],
		"weight": 100.0,
		"icon": preload("res://assets/icons/items/sandstone.png"),
	},
	5: {
		"name": "hematite",
		"type": ItemType.MINERAL,
		"subclasses": [ItemSubclass.RAW_ORE],
		"weight": 100.0,
		"icon": preload("res://assets/icons/items/hematite.png"),
	},
	6: {
		"name": "coal",
		"type": ItemType.MINERAL,
		"subclasses": [ItemSubclass.FUEL],
		"weight": 100.0,
		"icon": preload("res://assets/icons/items/coal.png"),
	},
	7: {
		"name": "crude_oil",
		"type": ItemType.LIQUID,
		"subclasses": [],
		"icon": preload("res://assets/icons/items/crude_oil.png"),
	},
	8: {
		"name": "petroleum",
		"type": ItemType.LIQUID,
		"subclasses": [ItemSubclass.FUEL],
		"icon": preload("res://assets/icons/items/petroleum.png"),
	},
	9: {
		"name": "PZGR88mm",
		"type": ItemType.MATERIAL,
		"subclasses": [ItemSubclass.AMMO],
		"weight": 7.0,
		"icon": preload("res://assets/icons/items/pzgr75.png"),
		"max_stack": 999,
		"shell_scene": preload("res://items/shells/ger/pzgr_88mm.tscn"),
	},
}

func get_item(item_id: int) -> Dictionary:
	return items.get(item_id, {})

func get_item_by_name(item_name: String) -> Dictionary:
	return get_item(get_id_by_name(item_name))

func get_id_by_name(item_name: String) -> int:
	for item_id: int in items:
		if items[item_id].get("name", "") == item_name:
			return item_id
	return INVALID_ITEM_ID

func has_item(item_id: int) -> bool:
	return items.has(item_id)

func get_display_name(item_name: String) -> String:
	if get_item_by_name(item_name).is_empty():
		return item_name
	if item_name != item_name.to_lower():
		return item_name
	return item_name.replace("_", " ").capitalize()

func get_items_by_type(item_type: int) -> Array[String]:
	var result: Array[String] = []
	for item_id: int in items:
		if items[item_id].get("type", -1) == item_type:
			result.append(items[item_id].get("name", ""))
	result.sort()
	return result

func has_subclass(item_name: String, subclass: int) -> bool:
	var subclasses: Array = get_item_by_name(item_name).get("subclasses", [])
	return subclasses.has(subclass)
