extends CharacterBody3D

##группы экспорта для удобства в редакторе
@export_group("Moving")
#чувствительность мыши
@export var mouse_sensitivity : float = 0.002

#скорость движения персонажа (без спринта)
@export var speed : float = 5.0

#скорость спринта персонажа
@export var sprint_speed : float = 16.0

#гравитация и прыжок
@export var gravity : float = 9.8
@export var jump_velocity : float = 4.5


@export_group("Stamina")

# максимальное значение выносливости
@export_range(1.0, 1000.0, 1.0) var max_stamina: float = 100.0

# продолжительность спринта
@export_range(0.1, 120.0, 0.1) var sprint_duration: float = 15.0

# продолжительность истощения выносливости
@export_range(0.1, 30.0, 0.1) var exhaustion_duration: float = 3.0

# продолжительность восстановления выносливости
@export_range(0.1, 120.0, 0.1) var stamina_recovery_duration: float = 20.0




@export_group("Camera")
# стандартное и спринтовое поле зрения камеры, а также скорость изменения поля зрения
@export var standard_fov : float = 80.0
@export var sprint_fov : float = 95.0
@export var fov_change_speed : float = 8

############################################################
##################### ССЫЛКИ НА НОДЫ #######################
############################################################

@onready var head : Node3D = $Head
@onready var camera : Camera3D = $Head/Camera3D
@onready var stamina_bar: Node = $HUD/StaminaBar
@onready var inventory_ui: InventoryUIController = $HUD/InventoryUI



#############################################################
#################### ПЕРЕМЕННЫЕ ДЛЯ СКРИПТА #################
#############################################################

# переменные для управления камерой
var fall_time: float
var bob_time: float
var lean_time: float
var current_stamina: float = 100.0
var exhaustion_time_left: float = 0.0
var is_sprinting: bool = false
var strong_fall: bool = false

# стартовые позиции камеры для эффектов покачивания и наклона
@onready var camera_start_position = camera.position
@onready var camera_start_rotation = camera.rotation

########################################################
#################### ФУНКЦИИ ГОДОТА ####################
########################################################

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	current_stamina = max_stamina
	stamina_bar.set("max_value", max_stamina)
	stamina_bar.call("set_value", current_stamina, false)

	# Terrain3D не всегда находит камеру, если она находится внутри инстанса Player.
	# Привязываем камеру и физическую зону Terrain3D после готовности всех узлов сцены.
	call_deferred("_setup_terrain_tracking")


func _setup_terrain_tracking() -> void:
	var world_root := get_parent()
	var terrain := world_root.get_node_or_null("terrain/Terrain3D")
	if terrain == null:
		push_warning("Player: не найден узел terrain/Terrain3D для привязки камеры.")
		return

	# Явно назначаем камеру Terrain3D.
	if terrain.has_method("set_camera"):
		terrain.call("set_camera", camera)

	# Для этой карты используем коллизии всех регионов, а не только динамическую
	# область вокруг камеры. Так физические предметы не зависят от обновления LOD.
	terrain.set("collision_mode", 3)


func _unhandled_input(event: InputEvent) -> void:
	# Пока открыт инвентарь, мышь управляет интерфейсом, а не камерой.
	if inventory_ui.is_open:
		return

	if event is InputEventMouseMotion:
		mouse_look(event)


func _physics_process(delta: float) -> void:
	# Не двигаем игрока и не обновляем игровые эффекты, пока открыт инвентарь.
	if inventory_ui.is_open:
		# Останавливаем горизонтальное движение, но сохраняем гравитацию.
		velocity.x = 0.0
		velocity.z = 0.0
		is_sprinting = false
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	moving(delta)
	sprint_effect(delta)
	fall_effect(delta, 20, 0.1)

####################################################################
############################## КАМЕРА ##############################
####################################################################


# Эффект спринта: покачивангие камеры и увеличение FOV
func sprint_effect(delta: float) -> void:
	if is_sprinting and Vector2(velocity.x, velocity.z).length() > 0:
		camera.fov = lerp(camera.fov, sprint_fov, fov_change_speed * delta)

		camera_lean(delta, lerp(0.5, 13.0, 0.7), lerp(0.0002, 0.01, 0.7))
		head_bob(delta, lerp(0.5, 12.0, 0.7), 0.03, 5, true)

		camera.position = Vector3(
			lerp(camera.position.x, camera.position.x + randf_range(-0.15, 0.15), 5 * delta),
			camera_start_position.y + sin(bob_time * 10) * 0.01,
			lerp(camera.position.z, camera.position.z + randf_range(-0.15, 0.15), 5 * delta)
		)
	else:
		camera.fov = lerp(camera.fov, standard_fov, fov_change_speed * delta)


# основная функция для управления камерой мышью
func mouse_look(event: InputEventMouseMotion) -> void:
	rotate_y(-event.relative.x * mouse_sensitivity)
	head.rotate_x(-event.relative.y * mouse_sensitivity)
	head.rotation.x = clampf(head.rotation.x, -PI/2, PI/2)


# функция для покачивания камеры при ходьбе
func head_bob(delta: float, frequency: float, amplitude: float, weight: float, rotation_amount: bool) -> void:
	if rotation_amount == false:
		if is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0:
			camera_lean(delta, 5, 0.003)

			bob_time += delta * frequency
			var bobbing_amount = sin(bob_time) * amplitude
			camera.position.y = camera_start_position.y + bobbing_amount
		else:
			camera.position.y = lerp(camera.position.y, camera_start_position.y, weight * delta)
	else:
		if is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0:
			bob_time += delta * frequency
			var bobbing_amount = clampf(sin(bob_time), -0.5, 0.5) * amplitude
			camera.rotation.x = camera_start_rotation.x + bobbing_amount
		else:
			camera.rotation.x = lerp(camera.rotation.x, camera_start_rotation.x, weight * delta)


# функция для наклона камеры в сторону движения и при спринте
func camera_lean(delta: float, frequency: float, amplitude: float) -> void:
	if frequency == 0 and amplitude == 0:
		var input_dir: Vector2 = Input.get_vector(
			"move_left",
			"move_right",
			"move_forward",
			"move_back"
		).normalized()
		var target_lean = -input_dir.x * 0.05
		var current_lean = camera.rotation.z
		camera.rotation.z = lerp(current_lean, target_lean, 5 * delta)
	else:
		lean_time += delta * frequency
		var lean_amount = clampf(sin(lean_time), -0.6, 0.6) * amplitude
		camera.rotation.z = camera.rotation.z + lean_amount


func fall_effect(delta: float, frequency: float, amplitude: float) -> void:
	if not is_on_floor() and velocity.y < -5:
		camera.rotation.x = lerp(camera.rotation.x, 1.0, 0.5 * delta)
	else:
		camera.rotation.x = lerp(camera.rotation.x, camera_start_rotation.x, 5 * delta)

	if not is_on_floor() and velocity.y < -10:
		strong_fall = true
		camera.rotation.z = randf_range(camera.rotation.z - lerp(0.01, 0.1, 0.5 * delta), camera.rotation.z + lerp(0.01, 0.1, 0.5 * delta))
	else:
		camera.rotation.z = lerp(camera.rotation.z, camera_start_rotation.z, 0.5 * delta)



	if is_on_floor() and strong_fall:
		#camera.rotation.x += -0.5
		strong_fall = false
		fall_time = 0.0



#######################################################################
############################### ДВИЖЕНИЕ ##############################
#######################################################################

func moving(delta: float) -> void:

	head_bob(delta, 10, 0.1, 5, false)
	var input_dir: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	var stamina_before := current_stamina
	var sprint_requested := Input.is_action_pressed("sprint") and input_dir.length() > 0.0
	var current_speed: float = speed
	var normal_sprint_speed := lerpf(speed, sprint_speed, 0.7)
	var exhaustion_speed := lerpf(speed, normal_sprint_speed, 0.5)
	is_sprinting = false

	if sprint_requested:
		if current_stamina > 0.0:
			is_sprinting = true
			current_speed = normal_sprint_speed

			var drain_rate := max_stamina / maxf(sprint_duration, 0.001)
			current_stamina = maxf(current_stamina - drain_rate * delta, 0.0)

			if is_zero_approx(current_stamina):
				current_stamina = 0.0
				exhaustion_time_left = exhaustion_duration
		elif exhaustion_time_left > 0.0:
			is_sprinting = true
			current_speed = exhaustion_speed
			exhaustion_time_left = maxf(exhaustion_time_left - delta, 0.0)
	else:
		exhaustion_time_left = 0.0

		if current_stamina < max_stamina:
			var recovery_rate := max_stamina / maxf(stamina_recovery_duration, 0.001)
			current_stamina = minf(current_stamina + recovery_rate * delta, max_stamina)

	if not is_equal_approx(stamina_before, current_stamina):
		stamina_bar.call("set_value", current_stamina)

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	if not is_on_floor():
		velocity.y -= gravity * delta

	move_and_slide()
