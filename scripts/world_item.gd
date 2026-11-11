@tool
class_name WorldItem
extends RigidBody3D
## Физический предмет, который можно подобрать через интерфейс interact(player).

const ITEM_CATALOG = preload("res://scripts/item_catalog.gd")

@export var item_id: StringName = &"metal_scrap":
	set(value):
		item_id = value
		_refresh_visual()

@export_range(1, 999, 1) var amount: int = 1:
	set(value):
		amount = maxi(value, 1)
		_refresh_visual()

@onready var visual: MeshInstance3D = $Visual
@onready var collision_shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	# Группа позволяет PlayerInteraction отличать предмет для подбора от
	# обычного физического объекта. Визуал и форма создаются из ItemDefinition.
	add_to_group("world_pickup")
	_refresh_visual()


# Вызывается PlayerInteraction после попадания луча и нажатия E.
# add_item возвращает остаток, который не поместился; только после успешного
# добавления уменьшаем стопку или удаляем физический узел из мира.
func interact(player: Node) -> bool:
	var inventory := player.get_node_or_null("InventoryData") as InventoryDataModel
	if inventory == null:
		return false

	var previous_amount := amount
	var remaining_amount := inventory.add_item(item_id, previous_amount)
	var picked_up := previous_amount - remaining_amount

	if picked_up <= 0:
		return false

	# Нулевой остаток означает, что узел нужно удалить. Свойство amount
	# хранит только положительное количество, поэтому не записываем в него 0.
	if remaining_amount <= 0:
		queue_free()
	else:
		amount = remaining_amount
		_refresh_visual()

	return true


# Создаёт визуальную копию предмета для удерживания перед камерой.
# Она не является RigidBody3D и поэтому не участвует в столкновениях мира.
static func create_visual(target_item_id: StringName) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = _make_mesh(target_item_id)
	result.material_override = _make_material(target_item_id)
	return result


# Синхронизирует Mesh, CollisionShape3D и массу с выбранным item_id и amount.
# Функция используется setter-ами в Inspector и в _ready(), поэтому предмет
# можно настраивать в сцене, не копируя параметры в несколько файлов.
func _refresh_visual() -> void:
	var visual_node := get_node_or_null("Visual") as MeshInstance3D
	var collision_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if visual_node == null or collision_node == null:
		return

	visual_node.mesh = _make_mesh(item_id)
	visual_node.material_override = _make_material(item_id)

	var shape := BoxShape3D.new()
	shape.size = _collision_size(item_id)
	collision_node.shape = shape
	mass = maxf(_weight_per_item(item_id) * float(maxi(amount, 1)), 0.1)


# Получает описание предмета из общего каталога вместо дублирования таблицы.
static func _get_definition(target_item_id: StringName) -> ItemDefinition:
	return ITEM_CATALOG.get_definition(target_item_id)


# Возвращает Mesh из ItemDefinition или простой запасной куб для неизвестного ID.
static func _make_mesh(target_item_id: StringName) -> Mesh:
	var definition := _get_definition(target_item_id)
	if definition != null and definition.world_mesh != null:
		return definition.world_mesh

	var fallback := BoxMesh.new()
	fallback.size = Vector3(0.2, 0.12, 0.2)
	return fallback


# Создаёт материал для предмета. Цвет берётся из описания, чтобы мир и UI
# использовали один и тот же визуальный идентификатор.
static func _make_material(target_item_id: StringName) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var definition := _get_definition(target_item_id)
	material.albedo_color = definition.display_color if definition != null else Color(0.5, 0.5, 0.5)
	material.roughness = 0.82
	return material


# Возвращает явно заданный размер физической формы. Он отделён от размера Mesh,
# потому что визуальная модель может содержать выступы или пустое пространство.
static func _collision_size(target_item_id: StringName) -> Vector3:
	var definition := _get_definition(target_item_id)
	if definition != null and definition.collision_size.x > 0.0 and definition.collision_size.y > 0.0 and definition.collision_size.z > 0.0:
		return definition.collision_size
	return _make_mesh(target_item_id).get_aabb().size * 1.1


# Возвращает массу одной единицы предмета; WorldItem умножает её на количество.
static func _weight_per_item(target_item_id: StringName) -> float:
	var definition := _get_definition(target_item_id)
	return definition.weight if definition != null else 0.8
