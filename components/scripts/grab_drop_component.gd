class_name GrabDropComponent
extends Node3D

@export_group("Перетаскивание предметов")
@export_range(25.0, 500.0, 5.0) var drag_stiffness: float = 160.0
@export_range(0.5, 1.5, 0.05) var damping_ratio: float = 1.0
@export_range(1.0, 20.0, 0.5) var target_smoothing: float = 7.0
@export_range(1.0, 100.0, 1.0) var max_lift_mass_kg: float = 25.0
@export_range(5.0, 30.0, 1.0) var max_drag_acceleration: float = 14.0

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
		if dragged_item.freeze:
			dragged_item = null
			return

		# Не даём захваченному предмету упираться в капсулу самого игрока.
		var player_body := get_parent() as PhysicsBody3D
		if player_body != null:
			dragged_item.add_collision_exception_with(player_body)

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

	var body_mass: float = maxf(dragged_item.mass, 0.01)

	# Учитываем вращение: при захвате за край точка имеет не только
	# поступательную, но и угловую скорость.
	var damping_axis := error.normalized()
	if damping_axis.is_zero_approx():
		damping_axis = point_velocity.normalized()

	var inverse_inertia := dragged_item.get_inverse_inertia_tensor()
	var lever_cross_axis := offset.cross(damping_axis)
	var inverse_effective_mass := (
		1.0 / body_mass
		+ lever_cross_axis.dot(inverse_inertia * lever_cross_axis)
	)
	var effective_mass := 1.0 / maxf(inverse_effective_mass, 0.0001)

	# Демпфирование с учётом эффективной массы точки захвата.
	var damping: float = 2.0 * sqrt(drag_stiffness * effective_mass) * damping_ratio
	var force: Vector3 = error * drag_stiffness - point_velocity * damping

	# Ограничиваем ускорение лёгких тел, иначе даже небольшой предмет
	# может получить чрезмерную скорость от пружины.
	# Отдельный предел по массе задаёт максимальный вес, который можно поднять.
	var world_gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var max_force_by_acceleration: float = body_mass * max_drag_acceleration
	var max_force_by_lift_mass: float = max_lift_mass_kg * world_gravity
	var max_force: float = minf(max_force_by_acceleration, max_force_by_lift_mass)
	force = force.limit_length(max_force)

	# apply_force принимает смещение от начала тела в мировых координатах.
	# Так сила остаётся приложенной именно в точке, куда попал RayCast.
	dragged_item.apply_force(force, offset)


func stop_item_dragging() -> void:
	if is_instance_valid(dragged_item):
		var player_body := get_parent() as PhysicsBody3D
		if player_body != null:
			dragged_item.remove_collision_exception_with(player_body)

	dragged_item = null
