class_name WeaponBlockInfoSection
extends VBoxContainer

var weapon: Weapon

@onready var state_label: Label = $State
@onready var ammo_label: Label = $Ammo
@onready var selection_label: Label = $Selection
@onready var reload_bar: ProgressBar = $ReloadBar
@onready var ammo_button: Button = $AmmoButton
@onready var ammo_popup: PopupPanel = $AmmoPopup
@onready var ammo_tree: Tree = $AmmoPopup/Margin/VBox/Tree

func _process(_delta: float) -> void:
	if is_instance_valid(weapon):
		_refresh()

func bind_block(block: Block) -> void:
	unbind_block()
	if not block is Weapon:
		return
	weapon = block as Weapon
	weapon.weapon_status_changed.connect(_refresh)
	_refresh()

func unbind_block() -> void:
	ammo_popup.hide()
	if is_instance_valid(weapon) and weapon.weapon_status_changed.is_connected(_refresh):
		weapon.weapon_status_changed.disconnect(_refresh)
	weapon = null

func _refresh() -> void:
	if not is_instance_valid(weapon):
		return
	state_label.text = "State: %s" % weapon.get_state_name()
	var loaded_name := "None"
	if not weapon.loaded_ammo_id.is_empty():
		loaded_name = ItemDB.get_display_name(weapon.loaded_ammo_id)
	ammo_label.text = "Chambered: %s" % loaded_name
	var selection_name := "First available"
	if not weapon.selected_ammo_id.is_empty():
		selection_name = ItemDB.get_display_name(weapon.selected_ammo_id)
	selection_label.text = "Ammo selection: %s" % selection_name
	reload_bar.value = weapon.get_reload_progress() * 100.0
	ammo_button.disabled = weapon.shells.is_empty()

func _on_ammo_button_pressed() -> void:
	if not is_instance_valid(weapon):
		return
	ammo_tree.clear()
	var root := ammo_tree.create_item()
	var first_available := ammo_tree.create_item(root)
	first_available.set_text(0, "First available")
	first_available.set_metadata(0, "")
	for item_id: String in weapon.shells:
		var item_data := ItemDB.get_item_by_name(item_id)
		if item_data.is_empty() or not ItemDB.has_subclass(item_id, ItemDB.ItemSubclass.AMMO):
			continue
		var leaf := ammo_tree.create_item(root)
		leaf.set_text(0, ItemDB.get_display_name(item_id))
		leaf.set_icon(0, item_data.get("icon"))
		leaf.set_metadata(0, item_id)
	ammo_popup.popup_centered(Vector2i(340, 300))

func _on_ammo_tree_item_selected() -> void:
	if not is_instance_valid(weapon):
		return
	var selected := ammo_tree.get_selected()
	if selected == null:
		return
	var metadata: Variant = selected.get_metadata(0)
	if not metadata is String:
		return
	weapon.select_ammo(metadata)
	ammo_popup.hide()
