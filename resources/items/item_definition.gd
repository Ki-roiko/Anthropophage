class_name ItemDefinition
extends Resource
## Описание предмета. Здесь только данные, без логики инвентаря.

@export var item_id: StringName
@export var display_name: String = "Предмет"
@export_multiline var description: String = ""
@export var size: Vector2i = Vector2i(1, 1)
@export_range(1, 999, 1) var max_stack_size: int = 1
@export var icon_symbol: String = "?"
@export var display_color: Color = Color.WHITE
@export var world_mesh: Mesh
@export_range(0.01, 1000.0, 0.01) var weight: float = 0.5
