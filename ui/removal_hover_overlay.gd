class_name RemovalHoverOverlay
extends Node2D

const STRIPE_ATLAS := preload("res://assets/icons/icons_small.png")
const STRIPE_REGION := Rect2(240, 80, 16, 16)

var _tiles: Array[Sprite2D] = []
var _centers: Array[Vector2] = []
var _stripe_texture: AtlasTexture


func _init() -> void:
	z_index = 1000
	_stripe_texture = AtlasTexture.new()
	_stripe_texture.atlas = STRIPE_ATLAS
	_stripe_texture.region = STRIPE_REGION
	hide()


func attach_to(host: Node2D) -> void:
	if not is_instance_valid(host) or get_parent() == host:
		return
	if get_parent() != null:
		get_parent().remove_child(self)
	host.add_child(self)
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE


func show_centers(centers: Array[Vector2]) -> void:
	if centers.is_empty():
		clear()
		return
	if centers == _centers:
		show()
		return
	_centers = centers.duplicate()
	while _tiles.size() < centers.size():
		var tile := Sprite2D.new()
		tile.texture = _stripe_texture
		tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(tile)
		_tiles.append(tile)
	for index in range(_tiles.size()):
		var tile := _tiles[index]
		tile.visible = index < centers.size()
		if tile.visible:
			tile.position = centers[index]
	show()


func clear() -> void:
	_centers.clear()
	hide()
