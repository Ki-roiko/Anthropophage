extends UIPanel
## Небольшая демонстрационная панель для проверки регистрации через Inspector.

# Кнопка закрытия является внутренней деталью панели и не требует изменений UIManager.
func _ready() -> void:
	var close_button := get_node_or_null("Window/Content/CloseButton") as Button
	if close_button != null:
		close_button.pressed.connect(close_panel)
