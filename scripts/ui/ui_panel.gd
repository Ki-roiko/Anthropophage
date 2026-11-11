class_name UIPanel
extends Control
## Минимальный контракт независимой панели для UIManager.

signal panel_opened(panel: UIPanel)
signal panel_closed(panel: UIPanel)

@export var panel_id: StringName
@export var open_action: StringName
@export_enum("exclusive", "overlay") var display_mode: String = "exclusive"

var is_open: bool = false

# Показывает панель и уведомляет UIManager. Внутренние данные панели здесь
# не обрабатываются: каждая панель сама решает, что делать при открытии.
func open_panel() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	panel_opened.emit(self)

# Скрывает панель и сообщает диспетчеру, что активное окно закрылось.
func close_panel() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	panel_closed.emit(self)

# Переключает состояние панели по команде UIManager или другой UI-системы.
func toggle_panel() -> void:
	if is_open:
		close_panel()
	else:
		open_panel()
