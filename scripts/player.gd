extends CharacterBody3D

## Контроллер игрока от первого лица: движение, спринт с выносливостью, эффекты камеры.
## Все настройки живут здесь (значения по умолчанию = реальные игровые значения),
## поэтому в player.tscn / world.tscn их переопределять не нужно.

@export_group("Moving")
## Чувствительность мыши
@export var mouse_sensitivity: float = 0.002
## Скорость ходьбы
@export var speed: float = 4.0
## Реальная скорость спринта
@export var sprint_speed: float = 6.8
## Скорость бега в состоянии истощения (выносливость кончилась)
@export var exhausted_speed: float = 5.4
@export var gravity: float = 29.4
@export var jump_velocity: float = 9.0
## Максимальный угол наклона головы вверх/вниз (в градусах)
@export_range(1.0, 90.0, 1.0) var max_pitch_degrees: float = 89.0

@export_group("Stamina")
## Максимальное значение выносливости
@export_range(1.0, 1000.0, 1.0) var max_stamina: float = 100.0
## Сколько секунд можно бежать с полной выносливостью
@export_range(0.1, 120.0, 0.1) var sprint_duration: float = 15.0
## Сколько секунд можно бежать в состоянии истощения
@export_range(0.1, 30.0, 0.1) var exhaustion_duration: float = 3.0
## Сколько секунд нужно на полное восстановление
@export_range(0.1, 120.0, 0.1) var stamina_recovery_duration: float = 20.0
## Доля выносливости, после которой снова разрешён спринт после истощения
@export_range(0.0, 1.0, 0.05) var sprint_resume_threshold: float = 0.2

@export_group("Camera")
@export var standard_fov: float = 90.0
@export var sprint_fov: float = 95.0
## Скорость сглаживания FOV и остальных эффектов камеры
@export var fov_change_speed: float = 8.0
@export var camera_smoothing: float = 10.0
## Покачивание камеры (наклон вверх-вниз) при ходьбе
@export var walk_bob_frequency: float = 10.0
@export var walk_bob_amplitude: float = 0.1
## Покачивание, наклон и тряска при спринте
@export var sprint_bob_frequency: float = 8.5
@export var sprint_bob_amplitude: float = 0.03
@export var sprint_roll_amount: float = 0.01
@export var sprint_shake_amount: float = 0.01
## Наклон камеры при движении вбок
@export var strafe_roll_amount: float = 0.05

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var stamina_bar: StatBar = $HUD/StaminaBar

var current_stamina: float = 0.0
var exhaustion_time_left: float = 0.0
var is_sprinting: bool = false
## true после полного истощения, пока выносливость не восстановится до порога
var sprint_locked: bool = false

var _bob_time: float = 0.0
var _shake_offset: Vector3 = Vector3.ZERO

@onready var _camera_start_position: Vector3 = camera.position
@onready var _camera_start_rotation: Vector3 = camera.rotation


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.fov = standard_fov
	current_stamina = max_stamina
	stamina_bar.max_value = max_stamina
	stamina_bar.set_value(current_stamina, false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	# Клик по окну возвращает захват мыши после Esc
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_look(event)


func _physics_process(delta: float) -> void:
	moving(delta)


# Визуальные эффекты камеры считаем каждый кадр, а не в физическом тике
func _process(delta: float) -> void:
	update_camera_effects(delta)


# ---------------------------------------------------------------- КАМЕРА ----

func mouse_look(event: InputEventMouseMotion) -> void:
	rotate_y(-event.relative.x * mouse_sensitivity)
	head.rotate_x(-event.relative.y * mouse_sensitivity)
	var limit := deg_to_rad(max_pitch_degrees)
	head.rotation.x = clampf(head.rotation.x, -limit, limit)


# Все эффекты считаются как целевое состояние камеры, к которому она плавно
# движется. Благодаря этому камера всегда возвращается в нейтраль, а результат
# не зависит от частоты кадров.
func update_camera_effects(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var is_moving := is_on_floor() and horizontal_speed > 0.1
	var smooth := 1.0 - exp(-camera_smoothing * delta)

	var target_fov := sprint_fov if (is_sprinting and horizontal_speed > 0.1) else standard_fov
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-fov_change_speed * delta))

	var target_position := _camera_start_position
	var target_pitch := _camera_start_rotation.x
	var target_roll := _camera_start_rotation.z
	var target_shake := Vector3.ZERO

	if is_moving:
		if is_sprinting:
			_bob_time += delta * sprint_bob_frequency
			target_position.y += sin(_bob_time) * sprint_bob_amplitude
			target_roll += sin(_bob_time * 0.5) * sprint_roll_amount
			target_shake = Vector3(
				randf_range(-1.0, 1.0),
				0.0,
				randf_range(-1.0, 1.0)
			) * sprint_shake_amount
		else:
			_bob_time += delta * walk_bob_frequency
			target_pitch += clampf(sin(_bob_time), -0.5, 0.5) * walk_bob_amplitude

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	target_roll += -input_dir.x * strafe_roll_amount

	_shake_offset = _shake_offset.lerp(target_shake, smooth)
	camera.position = camera.position.lerp(target_position + _shake_offset, smooth)
	camera.rotation.x = lerpf(camera.rotation.x, target_pitch, smooth)
	camera.rotation.z = lerpf(camera.rotation.z, target_roll, smooth)


# --------------------------------------------------------------- ДВИЖЕНИЕ ----

func moving(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var sprint_requested := Input.is_action_pressed("sprint") and input_dir.length() > 0.0
	var current_speed := speed
	is_sprinting = false

	if sprint_requested:
		if not sprint_locked and current_stamina > 0.0:
			is_sprinting = true
			current_speed = sprint_speed
			_drain_stamina(delta)
		elif exhaustion_time_left > 0.0:
			# Выносливость кончилась: ещё немного бежим медленнее, потом только шаг
			is_sprinting = true
			current_speed = exhausted_speed
			exhaustion_time_left = maxf(exhaustion_time_left - delta, 0.0)
	else:
		# Отпустили спринт: остаток «истощённого» бега не сохраняется,
		# поэтому его нельзя получить повторным нажатием
		exhaustion_time_left = 0.0
		_recover_stamina(delta)

	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	if not is_on_floor():
		velocity.y -= gravity * delta

	move_and_slide()


func _drain_stamina(delta: float) -> void:
	var drain_rate := max_stamina / maxf(sprint_duration, 0.001)
	current_stamina = maxf(current_stamina - drain_rate * delta, 0.0)

	if is_zero_approx(current_stamina):
		current_stamina = 0.0
		sprint_locked = true
		exhaustion_time_left = exhaustion_duration

	stamina_bar.set_value(current_stamina, false)


func _recover_stamina(delta: float) -> void:
	if current_stamina >= max_stamina:
		return

	var recovery_rate := max_stamina / maxf(stamina_recovery_duration, 0.001)
	current_stamina = minf(current_stamina + recovery_rate * delta, max_stamina)

	if sprint_locked and current_stamina >= max_stamina * sprint_resume_threshold:
		sprint_locked = false

	stamina_bar.set_value(current_stamina, false)
