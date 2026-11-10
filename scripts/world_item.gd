class_name WorldItem
extends RigidBody3D
## Физический предмет, который можно подобрать через интерфейс interact(player).

@export var item_id: StringName = &"metal_scrap"
@export_range(1, 999, 1) var amount: int = 1

@onready var visual: MeshInstance3D = $Visual
@onready var collision_shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	add_to_group("world_pickup")
	_refresh_visual()


## Общий интерфейс взаимодействия. Его могут реализовывать и другие объекты.
func interact(player: Node) -> bool:
	var inventory := player.get_node_or_null("InventoryData") as InventoryDataModel
	if inventory == null:
		return false

	var previous_amount := amount
	amount = inventory.add_item(item_id, amount)
	var picked_up := previous_amount - amount

	if picked_up <= 0:
		amount = previous_amount
		return false

	if amount <= 0:
		queue_free()
	else:
		_refresh_visual()

	return true


static func create_visual(target_item_id: StringName) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = _make_mesh(target_item_id)
	result.material_override = _make_material(target_item_id)
	return result


func _refresh_visual() -> void:
	if visual == null or collision_shape == null:
		return

	visual.mesh = _make_mesh(item_id)
	visual.material_override = _make_material(item_id)

	var shape := BoxShape3D.new()
	shape.size = _mesh_size(item_id) * 1.1
	collision_shape.shape = shape
	mass = maxf(_weight_per_item(item_id) * float(maxi(amount, 1)), 0.1)


static func _get_definition(target_item_id: StringName) -> ItemDefinition:
	return InventoryDataModel.ITEM_DEFINITIONS.get(target_item_id) as ItemDefinition


static func _make_mesh(target_item_id: StringName) -> Mesh:
	var definition := _get_definition(target_item_id)
	if definition != null and definition.world_mesh != null:
		return definition.world_mesh

	var fallback := BoxMesh.new()
	fallback.size = Vector3(0.2, 0.12, 0.2)
	return fallback


static func _make_material(target_item_id: StringName) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var definition := _get_definition(target_item_id)
	material.albedo_color = definition.display_color if definition != null else Color(0.5, 0.5, 0.5)
	material.roughness = 0.82
	return material


static func _mesh_size(target_item_id: StringName) -> Vector3:
	return _make_mesh(target_item_id).get_aabb().size


static func _weight_per_item(target_item_id: StringName) -> float:
	var definition := _get_definition(target_item_id)
	return definition.weight if definition != null else 0.8
