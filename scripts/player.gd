extends CharacterBody3D

## группы экспорта — чтобы настройки было удобно менять прямо в редакторе
@export_group("Moving")
# чувствительность мыши
@export var mouse_sensitivity: float = 0.002

# скорость движения персонажа (без спринта)
@export var speed: float = 5.0

# скорость спринта персонажа
@export var sprint_speed: float = 16.0

# гравитация и сила прыжка
@export var gravity: float = 9.8
@export var jump_velocity: float = 4.5


@export_group("Stamina")

# максимальное значение выносливости
@export_range(1.0, 1000.0, 1.0) var max_stamina: float = 100.0

# сколько секунд можно бежать на полной скорости
@export_range(0.1, 120.0, 0.1) var sprint_duration: float = 15.0

# сколько секунд персонаж ещё может бежать после полного истощения
@export_range(0.1, 30.0, 0.1) var exhaustion_duration: float = 3.0

# за сколько секунд выносливость восстановится с нуля до максимума
@export_range(0.1, 120.0, 0.1) var stamina_recovery_duration: float = 20.0


@export_group("Camera")

# обычное и спринтовое поле зрения камеры, а также скорость его изменения
@export var standard_fov: float = 80.0
@export var sprint_fov: float = 95.0
@export var fov_change_speed: float = 8.0


############################################################
##################### ССЫЛКИ НА НОДЫ #######################
############################################################

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var stamina_bar: Node = $HUD/StaminaBar


#############################################################
#################### ПЕРЕМЕННЫЕ ДЛЯ СКРИПТА #################
#############################################################

# таймеры для покачивания и наклона камеры
var bob_time: float = 0.0
var lean_time: float = 0.0

# текущая выносливость и время дополнительного бега после её истощения
var current_stamina: float = 100.0
var exhaustion_time_left: float = 0.0
var is_sprinting: bool = false

# случайное смещение камеры при спринте — цель хранится между кадрами
var sprint_shake_timer: float = 0.0
var sprint_shake_target: Vector3 = Vector3.ZERO

# запоминаем исходное положение камеры, чтобы все эффекты считались от него
@onready var camera_start_position: Vector3 = camera.position
@onready var camera_start_rotation: Vector3 = camera.rotation

const SPRINT_SHAKE_INTERVAL: float = 0.12
const SPRINT_SHAKE_AMOUNT: float = 0.15
const SPRINT_SHAKE_SPEED: float = 8.0


########################################################
#################### ФУНКЦИИ ГОДОТА ####################
########################################################

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	current_stamina = max_stamina
	stamina_bar.set("max_value", max_stamina)
	stamina_bar.call("set_value", current_stamina, false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_look(event)


func _physics_process(delta: float) -> void:
	moving(delta)

	# все эффекты камеры обновляем здесь и только один раз за кадр
	sprint_effect(delta)


####################################################################
############################## КАМЕРА ##############################
####################################################################

# здесь собираются все эффекты камеры: FOV, покачивание и наклон
func sprint_effect(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var has_movement := horizontal_speed > 0.1
	var sprint_effect_active := is_sprinting and has_movement

	var target_fov: float = sprint_fov if sprint_effect_active else standard_fov
	camera.fov = lerpf(
		camera.fov,
		target_fov,
		clampf(fov_change_speed * delta, 0.0, 1.0)
	)

	# при обычном движении камера покачивается вращением, при спринте — по высоте
	if sprint_effect_active:
		head_bob(delta, 8.55, 0.03, 5.0, true)
	else:
		head_bob(delta, 10.0, 0.1, 5.0, false)

	camera_lean(delta, sprint_effect_active)
	sprint_camera_shake(delta, sprint_effect_active)


# основная функция для управления камерой мышью
func mouse_look(event: InputEventMouseMotion) -> void:
	rotate_y(-event.relative.x * mouse_sensitivity)
	head.rotate_x(-event.relative.y * mouse_sensitivity)
	head.rotation.x = clampf(head.rotation.x, -PI / 2, PI / 2)


# покачивание камеры при ходьбе и спринте
func head_bob(
	delta: float,
	frequency: float,
	amplitude: float,
	reset_speed: float,
	use_position_bob: bool
) -> void:
	var has_movement := is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0.1
	var reset_weight := clampf(reset_speed * delta, 0.0, 1.0)

	if has_movement:
		bob_time += delta * frequency
		var bobbing_amount := sin(bob_time) * amplitude

		if use_position_bob:
			# на спринте камера подпрыгивает вверх-вниз
			camera.position.y = camera_start_position.y + bobbing_amount
			camera.rotation.x = lerpf(
				camera.rotation.x,
				camera_start_rotation.x,
				reset_weight
			)
		else:
			# при обычной ходьбе покачивание идёт через небольшой наклон
			camera.rotation.x = camera_start_rotation.x + clampf(
				bobbing_amount,
				-amplitude * 0.5,
				amplitude * 0.5
			)
			camera.position.y = lerpf(
				camera.position.y,
				camera_start_position.y,
				reset_weight
			)
	else:
		# если остановились или оказались в воздухе, камера спокойно возвращается в исходное положение
		camera.position.y = lerpf(
			camera.position.y,
			camera_start_position.y,
			reset_weight
		)
		camera.rotation.x = lerpf(
			camera.rotation.x,
			camera_start_rotation.x,
			reset_weight
		)


# наклоняем камеру в сторону движения; во время спринта добавляется лёгкое покачивание
func camera_lean(delta: float, sprint_active: bool) -> void:
	var input_dir: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	).normalized()

	var movement_lean: float = -input_dir.x * 0.05
	var sprint_lean: float = 0.0

	if sprint_active:
		lean_time += delta * 9.25
		sprint_lean = sin(lean_time) * 0.00706
	else:
		lean_time = 0.0

	# считаем наклон от исходного угла, а не прибавляем его к самому себе каждый кадр
	var target_lean: float = camera_start_rotation.z + movement_lean + sprint_lean
	camera.rotation.z = lerpf(
		camera.rotation.z,
		target_lean,
		clampf(5.0 * delta, 0.0, 1.0)
	)


# небольшое случайное смещение при спринте
func sprint_camera_shake(delta: float, shake_active: bool) -> void:
	if shake_active:
		sprint_shake_timer -= delta

		# новую случайную точку выбираем раз в несколько кадров, а не каждый кадр
		if sprint_shake_timer <= 0.0:
			sprint_shake_target = Vector3(
				randf_range(-SPRINT_SHAKE_AMOUNT, SPRINT_SHAKE_AMOUNT),
				0.0,
				randf_range(-SPRINT_SHAKE_AMOUNT, SPRINT_SHAKE_AMOUNT)
			)
			sprint_shake_timer = SPRINT_SHAKE_INTERVAL
	else:
		sprint_shake_target = Vector3.ZERO
		sprint_shake_timer = 0.0

	var shake_weight: float = clampf(SPRINT_SHAKE_SPEED * delta, 0.0, 1.0)

	# смещение всегда считается от стартовой позиции — камера не уплывает со временем
	camera.position.x = lerpf(
		camera.position.x,
		camera_start_position.x + sprint_shake_target.x,
		shake_weight
	)
	camera.position.z = lerpf(
		camera.position.z,
		camera_start_position.z + sprint_shake_target.z,
		shake_weight
	)


#######################################################################
############################### ДВИЖЕНИЕ ##############################
#######################################################################

func moving(delta: float) -> void:
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

	# обновляем полоску только когда значение действительно изменилось
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
