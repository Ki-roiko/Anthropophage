class_name ItemHoldComponent
extends Node

@onready var inventory_component: InventoryComponent = get_parent().get_node("InventoryComponent")
@onready var holding_point: Marker3D = $HoldingComponent

func spawn_holding_item(id: String, amount: int, properties) -> void:

	var path := inventory_component.get_item_scene_path(id)
	var packed_scene := load(path) as PackedScene
	var item := packed_scene.instantiate()

	item.item_id = id
	item.item_properties = properties

	add_child(item)
	item.global_transform = holding_point.global_transform
