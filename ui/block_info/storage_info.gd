class_name StorageBlockInfoSection
extends VBoxContainer

var target_block: Block

@onready var contents_list: VBoxContainer = $ContentsScroll/ContentsList
@onready var capacity_bar: ProgressBar = $CapacityBar
@onready var capacity_label: Label = $CapacityLabel
@onready var allowed_list: VBoxContainer = $AllowedScroll/AllowedList
@onready var add_button: Button = $AddButton
@onready var add_popup: PopupPanel = $AddPopup
@onready var add_tree: Tree = $AddPopup/Margin/VBox/Tree

func bind_block(block: Block) -> void:
	unbind_block()
	if not block is ItemStorage and not block is LiquidStorage:
		return
	target_block = block
	if target_block is ItemStorage:
		var storage := target_block as ItemStorage
		storage.contents_changed.connect(_refresh)
		storage.allowed_items_changed.connect(_refresh)
	else:
		var storage := target_block as LiquidStorage
		storage.contents_changed.connect(_refresh)
		storage.allowed_items_changed.connect(_refresh)
	_refresh()

func unbind_block() -> void:
	add_popup.hide()
	if not is_instance_valid(target_block):
		target_block = null
		return
	if target_block is ItemStorage:
		var storage := target_block as ItemStorage
		if storage.contents_changed.is_connected(_refresh):
			storage.contents_changed.disconnect(_refresh)
		if storage.allowed_items_changed.is_connected(_refresh):
			storage.allowed_items_changed.disconnect(_refresh)
	elif target_block is LiquidStorage:
		var storage := target_block as LiquidStorage
		if storage.contents_changed.is_connected(_refresh):
			storage.contents_changed.disconnect(_refresh)
		if storage.allowed_items_changed.is_connected(_refresh):
			storage.allowed_items_changed.disconnect(_refresh)
	target_block = null

func _refresh() -> void:
	if not is_instance_valid(target_block):
		return
	_clear_container(contents_list)
	_clear_container(allowed_list)
	if target_block is ItemStorage:
		_refresh_item_storage(target_block as ItemStorage)
	else:
		_refresh_liquid_storage(target_block as LiquidStorage)
	_refresh_allowed_items()

func _refresh_item_storage(storage: ItemStorage) -> void:
	var item_names: Array = storage.items.keys()
	item_names.sort()
	if item_names.is_empty():
		contents_list.add_child(_make_empty_label("Empty"))
	else:
		for item_name: String in item_names:
			var count := storage.get_item_count(item_name)
			var weight := float(ItemDB.get_item_by_name(item_name).get("weight", 0.0))
			contents_list.add_child(_make_item_row(
				item_name,
				"%d  (%.1f mass)" % [count, count * weight]
			))
	capacity_bar.max_value = maxf(float(storage.max_load), 1.0)
	capacity_bar.value = storage.get_total_load()
	capacity_label.text = "%.1f / %d mass" % [storage.get_total_load(), storage.max_load]

func _refresh_liquid_storage(storage: LiquidStorage) -> void:
	if storage.liquid.is_empty() or storage.stored <= 0.0:
		contents_list.add_child(_make_empty_label("Empty"))
	else:
		contents_list.add_child(_make_item_row(
			storage.liquid,
			"%.2f mass" % storage.stored
		))
	capacity_bar.max_value = maxf(storage.capacity, 1.0)
	capacity_bar.value = storage.stored
	capacity_label.text = "%.2f / %.2f mass" % [storage.stored, storage.capacity]

func _refresh_allowed_items() -> void:
	var item_names := _get_allowed_items()
	if item_names.is_empty():
		allowed_list.add_child(_make_empty_label("No items allowed"))
	for item_name: String in item_names:
		var button := Button.new()
		button.text = ItemDB.get_display_name(item_name)
		button.icon = ItemDB.get_item_by_name(item_name).get("icon")
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = "Click to remove this allowed item"
		button.pressed.connect(_remove_allowed_item.bind(item_name))
		allowed_list.add_child(button)
	add_button.disabled = _get_addable_items().is_empty()

func _make_item_row(item_name: String, amount_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(24.0, 24.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = ItemDB.get_item_by_name(item_name).get("icon")
	row.add_child(icon)
	var label := Label.new()
	label.text = "%s  %s" % [ItemDB.get_display_name(item_name), amount_text]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row

func _make_empty_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color(0.72, 0.72, 0.72)
	return label

func _clear_container(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _get_allowed_items() -> Array[String]:
	if target_block is ItemStorage:
		return (target_block as ItemStorage).allowed_items.duplicate()
	if target_block is LiquidStorage:
		return (target_block as LiquidStorage).allowed_items.duplicate()
	return []

func _get_addable_items() -> Array[String]:
	var compatible: Array[String] = []
	if target_block is ItemStorage:
		compatible = (target_block as ItemStorage).get_compatible_item_names()
	elif target_block is LiquidStorage:
		compatible = (target_block as LiquidStorage).get_compatible_item_names()
	for item_name: String in _get_allowed_items():
		compatible.erase(item_name)
	return compatible

func _remove_allowed_item(item_name: String) -> void:
	if target_block is ItemStorage:
		(target_block as ItemStorage).remove_allowed_item(item_name)
	elif target_block is LiquidStorage:
		(target_block as LiquidStorage).remove_allowed_item(item_name)

func _on_add_button_pressed() -> void:
	_build_add_tree()
	add_popup.popup_centered(Vector2i(360, 400))

func _build_add_tree() -> void:
	add_tree.clear()
	var root := add_tree.create_item()
	var categories := {}
	for item_name: String in _get_addable_items():
		var category_name := _get_item_category(item_name)
		var category: TreeItem = categories.get(category_name)
		if category == null:
			category = add_tree.create_item(root)
			category.set_text(0, category_name)
			category.set_selectable(0, false)
			categories[category_name] = category
		var leaf := add_tree.create_item(category)
		leaf.set_text(0, ItemDB.get_display_name(item_name))
		leaf.set_icon(0, ItemDB.get_item_by_name(item_name).get("icon"))
		leaf.set_metadata(0, item_name)

func _get_item_category(item_name: String) -> String:
	if ItemDB.has_subclass(item_name, ItemDB.ItemSubclass.RAW_ORE):
		return "Raw Ores"
	if ItemDB.has_subclass(item_name, ItemDB.ItemSubclass.AMMO):
		return "Ammunition"
	if ItemDB.has_subclass(item_name, ItemDB.ItemSubclass.FUEL):
		return "Fuels"
	if target_block is LiquidStorage:
		return "Other Liquids"
	if target_block is ItemStorage:
		var storage := target_block as ItemStorage
		if storage.storage_kind == ItemStorage.StorageKind.DUMP:
			return "Other Minerals"
	return "General Materials"

func _on_add_tree_item_selected() -> void:
	var selected := add_tree.get_selected()
	if selected == null:
		return
	var metadata: Variant = selected.get_metadata(0)
	if not metadata is String:
		return
	if target_block is ItemStorage:
		(target_block as ItemStorage).add_allowed_item(metadata)
	elif target_block is LiquidStorage:
		(target_block as LiquidStorage).add_allowed_item(metadata)
	add_popup.hide()
