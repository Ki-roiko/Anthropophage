extends Node

@onready var inventory: GridInventory = $"../Inventory"
@onready var drop_point: Marker3D = $"../../Head/DropPoint"


func _ready() -> void:
	inventory.request_drop_item.connect(item_dropper)


func _process(delta: float) -> void:
	pass

func item_dropper(id: String, properties: Dictionary):
	var defenition = inventory.database.get_item(id)
	var path = defenition.properties.get("dropped_item")
	var packed_scene := load(path) as PackedScene
	
	if packed_scene == null:
		return
	else:
		var item := packed_scene.instantiate() as WorldItem
		item.item_id = id
		item.item_properties = properties
		get_tree().current_scene.add_child(item)
		
		item.global_transform = drop_point.global_transform
