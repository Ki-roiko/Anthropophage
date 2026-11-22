class_name ItemHoldComponent
extends Node

@onready var inventory_component: InventoryComponent = get_parent().get_node("InventoryComponent") as InventoryComponent
@onready var holding_point: Marker3D = $HoldingPoint

func spawn_holding_item(id: String, amount: int, properties) -> void:

	var path := inventory_component.get_item_scene_path(id, "holding_item")
	var packed_scene := load(path) as PackedScene
	var item := packed_scene.instantiate()

	#item.item_properties = properties

	add_child(item)
	item.global_transform = holding_point.global_transform

func _process(delta: float) -> void:
	if get_child(2):
		get_child(2).global_transform = holding_point.global_transform
		get_child(2).global_rotate = holding_point.global_rotate
