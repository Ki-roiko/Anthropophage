extends Node
## Подбор, выбрасывание и удерживание предметов из инвентаря.
## Объекты мира взаимодействуют через метод interact(player).

const WORLD_ITEM_SCENE: PackedScene = preload("res://scenes/items/world_item.tscn")

@export_range(0.5, 10.0, 0.1) var interaction_distance: float = 3.0

@onready var player: CharacterBody3D = get_parent() as CharacterBody3D
@onready var camera: Camera3D = player.get_node("Head/Camera3D") as Camera3D
@onready var inventory: InventoryDataModel = player.get_node("InventoryData") as InventoryDataModel
@onready var inventory_ui: InventoryUIController = player.get_node("HUD/InventoryUI") as InventoryUIController
@onready var prompt_label: Label = player.get_node("HUD/InteractionPrompt") as Label

var _current_interactable: Node
var _held_socket: Node3D
var _held_visual: MeshInstance3D
var _held_item_id: StringName = &""


func _ready() -> void:
	# Held socket живёт на камере: визуальная модель предмета автоматически
	# следует за взглядом, пока физический объект ещё находится в инвентаре.
	_held_socket = Node3D.new()
	_held_socket.name = "HeldItemSocket"
	_held_socket.position = Vector3(0.28, -0.22, -0.62)
	camera.add_child(_held_socket)

	inventory_ui.equip_requested.connect(_equip_item)
	inventory_ui.drop_requested.connect(_drop_inventory_item)


# Каждый физический кадр обновляет объект под перекрестием и текст подсказки.
# Если инвентарь открыт, игровой луч отключается, чтобы UI не конфликтовал с E.
func _physics_process(_delta: float) -> void:
	if inventory_ui.is_open:
		_current_interactable = null
		prompt_label.text = ""
		return

	_update_interactable()


# Обрабатывает E для обычного взаимодействия и F для отпускания предмета в руках.
# Конкретный объект сам реализует interact(), поэтому PlayerInteraction не знает
# внутреннюю логику двери, контейнера или WorldItem.
func _unhandled_input(event: InputEvent) -> void:
	if inventory_ui.is_open:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			_try_interact()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F and _held_visual != null:
			_release_held_item()
			get_viewport().set_input_as_handled()


# Строит луч от камеры и поднимается по родителям найденного collider-а, пока
# не найдёт узел с interact(). Это позволяет использовать дочерний CollisionShape3D
# и разные типы интерактивных объектов.
func _update_interactable() -> void:
	_current_interactable = null

	var ray_from := camera.global_position
	var ray_to := ray_from - camera.global_basis.z * interaction_distance
	var query := PhysicsRayQueryParameters3D.create(
		ray_from,
		ray_to,
		1 | 2,
		[player.get_rid()]
	)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)

	if not hit.is_empty():
		# collider возвращается как Object. Оставляем его обычной ссылкой,
		# чтобы не потерять RigidBody3D при приведении типа из Dictionary.
		var candidate = hit.get("collider")
		while candidate != null:
			if candidate.has_method("interact"):
				_current_interactable = candidate
				break
			candidate = candidate.get_parent()

	if _current_interactable == null:
		prompt_label.text = _held_prompt()
		return

	var prompt := "E — взаимодействовать"
	if _current_interactable.has_method("get_interaction_prompt"):
		prompt = str(_current_interactable.call("get_interaction_prompt"))
	elif _current_interactable is WorldItem:
		var world_item := _current_interactable as WorldItem
		var definition := inventory.get_definition(world_item.item_id)
		if definition != null:
			prompt = "E — подобрать: %s" % definition.display_name

	if _held_visual != null:
		prompt += "\nF — отпустить предмет"
	prompt_label.text = prompt


# Возвращает подсказку для удерживаемого предмета, если луч ничего не нашёл.
func _held_prompt() -> String:
	if _held_visual != null:
		var definition := inventory.get_definition(_held_item_id)
		if definition != null:
			return "В руках: %s   •   F — отпустить" % definition.display_name
	return ""


# Вызывает общий интерфейс взаимодействия у объекта, выбранного лучом.
func _try_interact() -> void:
	if _current_interactable == null or not is_instance_valid(_current_interactable):
		return

	if _current_interactable.has_method("interact"):
		_current_interactable.call("interact", player)


# Переносит одну единицу из инвентаря в визуальный объект перед камерой.
# Реальная физическая модель появится только при отпускании.
func _equip_item(item_uid: int) -> void:
	var entry := inventory.get_item(item_uid)
	if entry.is_empty():
		return

	var item_id := StringName(entry.get("item_id", ""))
	if inventory.get_definition(item_id) == null:
		return

	# При смене предмета старый сначала аккуратно отпускается в мир.
	if _held_visual != null:
		_release_held_item()

	if inventory.remove_item(item_uid, 1) <= 0:
		return

	_held_item_id = item_id
	_held_visual = WorldItem.create_visual(item_id)
	_held_socket.add_child(_held_visual)
	_held_visual.position = Vector3.ZERO
	_held_visual.rotation = Vector3.ZERO

	inventory_ui.close_inventory()


# Сначала создаёт физический предмет в мире, и только после успеха удаляет
# стопку из инвентаря. Такой порядок защищает предмет от потери при ошибке.
func _drop_inventory_item(item_uid: int) -> void:
	var entry := inventory.get_item(item_uid)
	if entry.is_empty():
		return

	var item_id := StringName(entry.get("item_id", ""))
	var amount := int(entry.get("amount", 0))
	var forward := -camera.global_basis.z
	var world_item := _create_world_item(
		item_id,
		amount,
		camera.global_position + forward * 1.0,
		forward * 1.8 + Vector3.UP * 0.65
	)
	if world_item == null:
		return

	var removed := inventory.remove_item(item_uid, amount)
	if removed != amount:
		world_item.queue_free()


# Выпускает удерживаемый предмет в мир с небольшим импульсом вперёд.
# Визуальная копия удаляется только после успешного создания WorldItem.
func _release_held_item() -> void:
	if _held_visual == null:
		return

	var forward := -camera.global_basis.z
	var world_item := _create_world_item(
		_held_item_id,
		1,
		camera.global_position + forward * 1.0,
		forward * 1.7 + Vector3.UP * 0.55
	)
	if world_item == null:
		return

	_held_visual.queue_free()
	_held_visual = null
	_held_item_id = &""


# Создаёт полноценный RigidBody3D из PackedScene, добавляет его в World и
# прикладывает импульс. Возвращает объект, чтобы вызывающий код мог безопасно
# завершить операцию инвентаря только после успешного создания.
func _create_world_item(
	item_id: StringName,
	amount: int,
	spawn_position: Vector3,
	impulse: Vector3
) -> WorldItem:
	var world_item := WORLD_ITEM_SCENE.instantiate() as WorldItem
	if world_item == null:
		push_error("PlayerInteraction: не удалось создать WorldItem для '%s'." % item_id)
		return null

	world_item.item_id = item_id
	world_item.amount = maxi(amount, 1)

	var world_root := get_tree().current_scene
	if world_root == null:
		world_root = player.get_parent()
	if world_root == null:
		push_error("PlayerInteraction: не найден корень сцены для выброшенного предмета.")
		world_item.free()
		return null
	world_root.add_child(world_item)

	world_item.global_position = spawn_position
	world_item.apply_central_impulse(impulse)
	return world_item
