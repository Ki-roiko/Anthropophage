class_name ItemCatalog
extends RefCounted
## Единый список описаний предметов.
## Экземпляр предмета хранит только item_id и количество, а все общие
## свойства предмета берутся отсюда.

const DEFINITIONS: Dictionary = {
	&"bandage": preload("res://resources/items/bandage.tres"),
	&"metal_scrap": preload("res://resources/items/metal_scrap.tres"),
	&"toolbox": preload("res://resources/items/toolbox.tres"),
}


# Возвращает общее описание типа предмета по его ID.
# InventoryDataModel использует его для размера и стаков, а WorldItem —
# для Mesh, цвета, массы и CollisionShape3D.
static func get_definition(item_id: StringName) -> ItemDefinition:
	return DEFINITIONS.get(item_id) as ItemDefinition


# Быстро проверяет, зарегистрирован ли ID предмета в каталоге.
# Это удобно для диагностики повреждённых данных сохранения.
static func contains(item_id: StringName) -> bool:
	return DEFINITIONS.has(item_id)
