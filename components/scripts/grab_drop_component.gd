class_name GrabDropComponent
extends Node3D

@export_group("Перетаскивание предметов")
@export_range(5.0, 200.0, 1.0) var drag_stiffness: float = 65.0
@export_range(1.0, 60.0, 1.0) var drag_damping: float = 18.0
@export_range(1.0, 40.0, 0.5) var target_smoothing: float = 14.0
@export_range(0.0, 1.0, 0.05) var mass_influence: float = 0.65
@export_range(100.0, 10000.0, 100.0) var max_drag_force: float = 2500.0

@onready var ray: RayCast3D = $RayCast3D
@onready var inventory_component: InventoryComponent = get_parent().get_node("InventoryComponent") as InventoryComponent
@onready var drop_point: Marker3D = $DropPoint

var dragged_item: RigidBody3D
var dragged_local_point: Vector3
var drag_distance: float
var drag_target_point: Vector3


func _ready() -> void:
	inventory_component.inventory.request_drop_item.connect(item_dropper)


func _unhandled_input(event: InputEvent) -> void:
	if inventory_component.is_inventory_open():
		return

	if event.is_action_pressed("inventory_interact"):
		grab_item()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if inventory_component.is_inventory_open():
		stop_item_dragging()
		return

	if Input.is_action_pressed("left_click"):
		item_dragging(delta)
	else:
		stop_item_dragging()


func grab_item() -> void:
	ray.force_raycast_update()

	if not ray.is_colliding():
		return

	var grabbing_item = ray.get_collider()
	if grabbing_item is WorldItem:
		if inventory_component.add_item(
			grabbing_item.item_id,
			1,
			grabbing_item.item_properties
		) == 0:
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


func item_dragging(delta: float) -> void:
	# Захватываем новый объект только если это RigidBody3D.
	if not is_instance_valid(dragged_item):
		dragged_item = null
		ray.force_raycast_update()

		if not ray.is_colliding():
			return

		var collider: Object = ray.get_collider()
		if not (collider is RigidBody3D):
			return

		dragged_item = collider as RigidBody3D

		# Сохраняем именно точку поверхности, в которую попал RayCast.
		var hit_point: Vector3 = ray.get_collision_point()
		dragged_local_point = dragged_item.to_local(hit_point)
		drag_distance = ray.global_position.distance_to(hit_point)

		# Начинаем сглаживание с исходной точки, чтобы не было рывка.
		drag_target_point = hit_point
		dragged_item.sleeping = false

	# Получаем текущее положение сохранённой точки захвата в мировых координатах.
	var grab_point: Vector3 = dragged_item.to_global(dragged_local_point)

	# Находим желаемое положение точки на прежнем расстоянии от RayCast.
	var direction: Vector3 = (ray.global_basis * ray.target_position).normalized()
	var desired_target_point: Vector3 = ray.global_position + direction * drag_distance

	# Плавно перемещаем цель вслед за камерой.
	var smoothing_weight: float = 1.0 - exp(-target_smoothing * delta)
	drag_target_point = drag_target_point.lerp(desired_target_point, smoothing_weight)

	# Смещение точки захвата относительно начала RigidBody3D.
	var offset: Vector3 = grab_point - dragged_item.global_position

	# Скорость именно точки захвата, включая вращение тела.
	var point_velocity: Vector3 = (
		dragged_item.linear_velocity
		+ dragged_item.angular_velocity.cross(offset)
	)

	var error: Vector3 = drag_target_point - grab_point

	# При mass_influence = 0 сила растёт пропорционально массе:
	# предметы разной массы получают примерно одинаковое ускорение.
	# При mass_influence = 1 сила растёт только как sqrt(mass):
	# тяжёлые предметы заметно медленнее разгоняются и поднимаются.
	var body_mass: float = maxf(dragged_item.mass, 0.01)
	var stiffness_scale: float = pow(body_mass, 1.0 - mass_influence * 0.5)

	# Подбираем демпфирование с учётом эффективной жёсткости и массы,
	# чтобы тяжёлые предметы не начинали чрезмерно раскачиваться.
	var damping_scale: float = sqrt(body_mass * stiffness_scale)

	var force: Vector3 = (
		error * drag_stiffness * stiffness_scale
		- point_velocity * drag_damping * damping_scale
	)

	# Ограничиваем силу, чтобы резкие движения камеры не дёргали физику.
	force = force.limit_length(max_drag_force)

	# Прикладываем силу в точке захвата, а не в центре тела.
	dragged_item.apply_force(force, offset)


func stop_item_dragging() -> void:
	dragged_item = null
