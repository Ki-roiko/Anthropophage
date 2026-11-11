class_name ItemDefinition
extends Resource
## Описание предмета. Здесь только данные, без логики инвентаря.

# Уникальный ключ, по которому ItemCatalog и экземпляры предметов находят
# это описание. Сам предмет в мире и запись в инвентаре хранят только этот ключ.
@export var item_id: StringName
# Текстовые и визуальные данные используются UI, подсказками и моделью предмета.
@export var display_name: String = "Предмет"
@export_multiline var description: String = ""
# Размер в клетках инвентаря. При повороте UI меняет местами X и Y.
@export var size: Vector2i = Vector2i(1, 1)
# Максимальное количество одинаковых предметов в одной записи инвентаря.
@export_range(1, 999, 1) var max_stack_size: int = 1
@export var icon_symbol: String = "?"
@export var display_color: Color = Color.WHITE
# Mesh используется WorldItem для визуального представления в 3D.
@export var world_mesh: Mesh
# Физический размер отдельный от Mesh: видимая модель может иметь пустые поля,
# а столкновение должно оставаться простым и предсказуемым.
@export var collision_size: Vector3 = Vector3(0.3, 0.2, 0.3)
@export_range(0.01, 1000.0, 0.01) var weight: float = 0.5
