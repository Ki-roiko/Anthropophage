class_name ItemHoldComponent
extends Node

@onready var inventory_component: InventoryComponent = get_parent().get_node("InventoryComponent") as InventoryComponent
@onready var holding_point: Marker3D = get_node("../Head/Camera3D/HoldingPoint")

func spawn_holding_item(id: String, amount: int, properties) -> void:

	var path := inventory_component.get_item_scene_path(id, "holding_item")
	var packed_scene := load(path) as PackedScene
	var item := packed_scene.instantiate()

	#item.item_properties = properties

	holding_point.add_child(item)
	item.transform = Transform3D.IDENTITY
	item.global_transform = holding_point.global_transform
