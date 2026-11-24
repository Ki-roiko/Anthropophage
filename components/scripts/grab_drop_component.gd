class_name GrabDropComponent
extends Node3D

@onready var ray: RayCast3D = $RayCast3D
@onready var inventory_component: InventoryComponent = get_parent().get_node("InventoryComponent") as InventoryComponent
@onready var drop_point: Marker3D = $DropPoint

var dragged_item: RigidBody3D
var dragged_local_point: Vector3
var drag_distance: float

func _ready() -> void:
	inventory_component.inventory.request_drop_item.connect(item_dropper)


func _unhandled_input(event: InputEvent) -> void:
	if inventory_component.is_inventory_open():
		return

	if event.is_action_pressed("inventory_interact"):
		grab_item()
		get_viewport().set_input_as_handled()

	if event.is_action_pressed("left-click"):
		item_dragging()
	else:
		stop_item_dragging()





func grab_item():
	if ray.is_colliding():
		var grabbing_item = ray.get_collider()
		if grabbing_item is WorldItem:
			if inventory_component.add_item(grabbing_item.item_id, 1, grabbing_item.item_properties) == 0:
				grabbing_item.queue_free()



func item_dropper(id: String, amount: int, properties: Dictionary) -> void:
	if amount <= 0:
		return

	var path := inventory_component.get_item_properties(id, "dropped_item")
	if path.is_empty():
		push_warning("Cannot find dropped item scene for '%s'." % id)
		return

	var packed_scene := load(path) as PackedScene
	if packed_scene == null:
		push_error("Cannot load dropped item scene: %s" % path)
		return

	var item := packed_scene.instantiate() as WorldItem
	if item == null:
		push_error("Dropped item scene does not have a WorldItem root: %s" % path)
		return

	var scene_root := get_tree().current_scene
	if scene_root == null:
		item.free()
		push_error("Cannot drop item: current scene is null.")
		return

	item.item_mesh = inventory_component.get_item_properties(id, "dropped_mesh")
	item.item_id = id
	item.item_properties = properties
	scene_root.add_child(item)
	item.global_transform = drop_point.global_transform


func item_dragging() -> void:
	# Если предмет ещё не захвачен — пробуем захватить его
	if not is_instance_valid(dragged_item):
		dragged_item = null

		ray.force_raycast_update()

		if not ray.is_colliding():
			return

		var hit_point: Vector3 = ray.get_collision_point()
		var collider := ray.get_collider() as RigidBody3D

		if collider == null:
			return

		dragged_item = collider

		# Запоминаем точку захвата относительно предмета
		dragged_local_point = dragged_item.to_local(hit_point)

		# Запоминаем дистанцию от камеры до точки захвата
		drag_distance = ray.global_position.distance_to(hit_point)

		dragged_item.sleeping = false

	# Получаем актуальное положение точки захвата
	var grab_point: Vector3 = dragged_item.to_global(dragged_local_point)

	# Получаем направление луча
	var direction: Vector3 = (
		ray.global_transform.basis * ray.target_position
	).normalized()

	# Вычисляем желаемое положение точки захвата
	var target_point: Vector3 = (
		ray.global_position + direction * drag_distance
	)

	# Смещение точки захвата относительно центра тела
	var offset: Vector3 = grab_point - dragged_item.global_position

	# Вычисляем скорость точки с учётом вращения предмета
	var point_velocity: Vector3 = (
		dragged_item.linear_velocity
		+ dragged_item.angular_velocity.cross(offset)
	)

	# Вычисляем отклонение от желаемого положения
	var error: Vector3 = target_point - grab_point

	# Рассчитываем силу притяжения и демпфирования
	var force: Vector3 = (
		error * 30.0 - point_velocity * 11.0
	) * dragged_item.mass

	# Прикладываем силу непосредственно в точке захвата
	dragged_item.apply_force(force, offset)

func stop_item_dragging() -> void:
	dragged_item = null