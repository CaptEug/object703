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

# item_id is always the integer dictionary key. item_name is the stable String
# used by recipes, allowed-item lists, and other developer-authored data.
var items := {
	1: {
		"item_name": "scrap",
		"display_name": "Scrap",
		"type": ItemType.MATERIAL,
		"subclasses": [],
		"weight": 100.0,
		"icon": preload("res://assets/icons/items/scrap.png"),
	},
	2: {
		"item_name": "metal",
		"display_name": "Metal",
		"type": ItemType.MATERIAL,
		"subclasses": [],
		"weight": 100.0,
		"icon": preload("res://assets/icons/items/metal.png"),
	},
	3: {
		"item_name": "metal_parts",
		"display_name": "Metal Parts",
		"type": ItemType.MATERIAL,
		"subclasses": [],
		"weight": 25.0,
		"icon": preload("res://assets/icons/items/metal.png"),
	},
	4: {
		"item_name": "sandstone",
		"display_name": "Sandstone",
		"type": ItemType.MINERAL,
		"subclasses": [],
		"weight": 100.0,
		"icon": preload("res://assets/icons/items/sandstone.png"),
	},
	5: {
		"item_name": "hematite",
		"display_name": "Hematite",
		"type": ItemType.MINERAL,
		"subclasses": [ItemSubclass.RAW_ORE],
		"weight": 100.0,
		"icon": preload("res://assets/icons/items/hematite.png"),
	},
	6: {
		"item_name": "coal",
		"display_name": "Coal",
		"type": ItemType.MINERAL,
		"subclasses": [ItemSubclass.FUEL],
		"weight": 100.0,
		"icon": preload("res://assets/icons/items/coal.png"),
	},
	7: {
		"item_name": "crude_oil",
		"display_name": "Crude Oil",
		"type": ItemType.LIQUID,
		"subclasses": [],
		"icon": preload("res://assets/icons/items/crude_oil.png"),
	},
	8: {
		"item_name": "petroleum",
		"display_name": "Petroleum",
		"type": ItemType.LIQUID,
		"subclasses": [ItemSubclass.FUEL],
		"icon": preload("res://assets/icons/items/petroleum.png"),
	},
	9: {
		"item_name": "PZGR88mm",
		"display_name": "PzGr 88 mm",
		"type": ItemType.MATERIAL,
		"subclasses": [ItemSubclass.AMMO],
		"weight": 7.0,
		"icon": preload("res://assets/icons/items/pzgr75.png"),
		"shell_scene": preload("res://items/shells/ger/pzgr_88mm.tscn"),
	},
}


func get_item(item_id: int) -> Dictionary:
	return items.get(item_id, {})


func get_item_by_name(item_name: String) -> Dictionary:
	return get_item(get_id_by_name(item_name))


func get_id_by_name(item_name: String) -> int:
	for item_id: int in items:
		if items[item_id].get("item_name", "") == item_name:
			return item_id
	return INVALID_ITEM_ID


func get_item_name(item_id: int) -> String:
	return str(get_item(item_id).get("item_name", ""))


func has_item(item_id: int) -> bool:
	return items.has(item_id)


func has_item_name(item_name: String) -> bool:
	return get_id_by_name(item_name) != INVALID_ITEM_ID


func get_display_name(item_name: String) -> String:
	var definition := get_item_by_name(item_name)
	if definition.is_empty():
		return item_name
	return str(
		definition.get(
			"display_name",
			item_name.replace("_", " ").capitalize()
		)
	)


func get_items_by_type(item_type: int) -> Array[String]:
	var result: Array[String] = []
	for item_id: int in items:
		if items[item_id].get("type", -1) == item_type:
			result.append(str(items[item_id].get("item_name", "")))
	result.sort()
	return result


func has_subclass(item_name: String, subclass: int) -> bool:
	var subclasses: Array = get_item_by_name(item_name).get("subclasses", [])
	return subclasses.has(subclass)
