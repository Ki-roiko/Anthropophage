extends Node3D
## Дополняет тестовую сцену предметами, если старый PackedScene не содержит
## их инстансы после загрузки. Позиция рассчитывается от данных Terrain3D.

const WORLD_ITEM_SCENE: PackedScene = preload("res://scenes/items/world_item.tscn")
const CRATE_SCENE: PackedScene = preload("res://scenes/items/physics_crate.tscn")

const ITEM_POSITIONS := {
	&"BandagePickup": Vector3(-255.7, 0.0, -259.2),
	&"MetalScrapPickup": Vector3(-254.6, 0.0, -260.2),
	&"ToolboxPickup": Vector3(-256.8, 0.0, -260.0),
}


func _ready() -> void:
	call_deferred("_ensure_test_objects")


func _ensure_test_objects() -> void:
	await get_tree().process_frame
	var world := get_parent()
	var terrain := world.get_node_or_null("terrain/Terrain3D")
	if terrain == null:
		push_error("WorldSetup: Terrain3D не найден, тестовые предметы не созданы.")
		return

	for item_name in [&"BandagePickup", &"MetalScrapPickup", &"ToolboxPickup"]:
		var existing_item := world.get_node_or_null(String(item_name)) as WorldItem
		if existing_item != null:
			existing_item.global_position = _safe_spawn_position(terrain, ITEM_POSITIONS[item_name])
			continue
		var item := WORLD_ITEM_SCENE.instantiate() as WorldItem
		if item == null:
			continue
		item.name = item_name
		item.item_id = _item_id_for_name(item_name)
		item.amount = 4 if item_name == &"MetalScrapPickup" else 1
		world.add_child(item)
		item.global_position = _safe_spawn_position(terrain, ITEM_POSITIONS[item_name])

	if world.get_node_or_null("PhysicsCrate") == null:
		var crate := CRATE_SCENE.instantiate() as RigidBody3D
		if crate != null:
			crate.name = &"PhysicsCrate"
			world.add_child(crate)
			crate.global_position = _safe_spawn_position(terrain, Vector3(-255.7, 0.0, -260.5))
	else:
		var existing_crate := world.get_node_or_null("PhysicsCrate") as RigidBody3D
		if existing_crate != null:
			existing_crate.global_position = _safe_spawn_position(terrain, Vector3(-255.7, 0.0, -260.5))


func _safe_spawn_position(terrain: Node, horizontal_position: Vector3) -> Vector3:
	var height := float(terrain.get("data").call("get_height", horizontal_position))
	if is_nan(height) or is_inf(height):
		height = 2.0
	return Vector3(horizontal_position.x, height + 3.0, horizontal_position.z)


func _item_id_for_name(item_name: StringName) -> StringName:
	match item_name:
		&"BandagePickup":
			return &"bandage"
		&"ToolboxPickup":
			return &"toolbox"
		_:
			return &"metal_scrap"
