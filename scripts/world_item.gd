extends RigidBody3D
class_name WorldItem

@export var item_name: String
@export var item_id: String
@export var item_properties: Dictionary
@export var item_mesh: PackedScene

func _ready() -> void:
	item_mesh.instantiate()
