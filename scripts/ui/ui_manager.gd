class_name UIManager
extends Control
## Универсальный диспетчер UI-панелей. Игровой логики здесь быть не должно.

@export var panel_scenes: Array[PackedScene] = []
@export var close_on_escape: bool = true

var registered_panels: Dictionary = {}
var active_panel: UIPanel
var _mouse_mode_before_ui: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _mouse_mode_saved: bool = false
var _registered: bool = false

# Создаёт панели из списка Inspector и назначает общую Theme корневому GameUI.
# UIManager хранит только ссылки и не знает содержимое конкретных окон.
func _ready() -> void:
	_register_panels()
	set_process_unhandled_input(true)

# Инстанцирует все PackedScene из Inspector, проверяет их UIPanel и уникальность ID.
# Неправильная сцена пропускается с ошибкой, чтобы одна панель не ломала остальные.
func _register_panels() -> void:
	if _registered:
		return
	_registered = true
	for panel_scene in panel_scenes:
		if panel_scene == null:
			continue
		var panel := panel_scene.instantiate() as UIPanel
		if panel == null:
			push_error("UIManager: сцена панели должна иметь корень UIPanel.")
			continue
		if panel.panel_id == &"":
			push_error("UIManager: у панели отсутствует panel_id.")
			panel.queue_free()
			continue
		if registered_panels.has(panel.panel_id):
			push_error("UIManager: дублирующийся panel_id '%s'." % panel.panel_id)
			panel.queue_free()
			continue
		panel.visible = false
		panel.panel_opened.connect(_on_panel_opened)
		panel.panel_closed.connect(_on_panel_closed)
		add_child(panel)
		registered_panels[panel.panel_id] = panel

# Возвращает зарегистрированную панель по ID. Игровая система использует эту
# ссылку только для своей панели, а UIManager не вызывает её специфические методы.
func get_panel(panel_id: StringName) -> UIPanel:
	return registered_panels.get(panel_id) as UIPanel

# Открывает панель. Для exclusive сначала закрывает другие exclusive-панели.
func open_panel(panel_id: StringName) -> void:
	var panel := get_panel(panel_id)
	if panel == null:
		push_warning("UIManager: панель '%s' не зарегистрирована." % panel_id)
		return
	if panel.display_mode == "exclusive":
		for other in registered_panels.values():
			if other != panel and other.is_open and other.display_mode == "exclusive":
				other.close_panel()
	panel.open_panel()

# Закрывает одну панель. Состояние мыши пересчитывается после сигнала закрытия.
func close_panel(panel_id: StringName) -> void:
	var panel := get_panel(panel_id)
	if panel != null:
		panel.close_panel()

# Переключает панель без знания её внутренней логики.
func toggle_panel(panel_id: StringName) -> void:
	var panel := get_panel(panel_id)
	if panel == null:
		return
	if panel.is_open:
		panel.close_panel()
	else:
		open_panel(panel_id)

# Возвращает true, если хотя бы одно окно сейчас блокирует игровой ввод.
func has_open_panel() -> bool:
	for panel in registered_panels.values():
		if panel.is_open:
			return true
	return false

# Обрабатывает Escape и действия открытия, не разбирая содержимое панелей.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if close_on_escape and event.keycode == KEY_ESCAPE and has_open_panel():
			_close_top_panel()
			get_viewport().set_input_as_handled()
			return
		for panel in registered_panels.values():
			if panel.open_action != &"" and event.is_action_pressed(panel.open_action):
				panel.toggle_panel()
				get_viewport().set_input_as_handled()
				return

# Сохраняет режим мыши перед первым окном и возвращает его только после закрытия
# последней панели. Поэтому overlay-панель не разблокирует игрока случайно.
func _on_panel_opened(panel: UIPanel) -> void:
	# Сигнал приходит после того, как UIPanel уже поставила is_open = true.
	# Поэтому проверяем отдельный флаг, а не has_open_panel(): иначе первый
	# открытый экран выглядел бы так, будто другой экран уже был открыт.
	if not _mouse_mode_saved:
		_mouse_mode_before_ui = Input.mouse_mode
		_mouse_mode_saved = true
	_input_mouse_visible()
	if panel.display_mode == "exclusive":
		active_panel = panel

# Пересчитывает активное окно и режим мыши после закрытия панели.
func _on_panel_closed(panel: UIPanel) -> void:
	if active_panel == panel:
		active_panel = null
	if not has_open_panel():
		Input.mouse_mode = _mouse_mode_before_ui
		_mouse_mode_saved = false
	else:
		_input_mouse_visible()

# Устанавливает видимый курсор для работы с любым открытым окном.
func _input_mouse_visible() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# Закрывает верхнюю открытую панель: сначала active_panel, затем последнюю найденную.
func _close_top_panel() -> void:
	if active_panel != null and active_panel.is_open:
		active_panel.close_panel()
		return
	for panel in registered_panels.values():
		if panel.is_open:
			panel.close_panel()
			return
