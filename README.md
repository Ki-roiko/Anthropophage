# Anthropophage

3D-игра от первого лица на Godot 4 (проект «3d voxel»).

## Запуск

1. Откройте `project.godot` в Godot (версия указана в `config/features` файла `project.godot`).
2. Убедитесь, что включён плагин **Terrain3D** (*Project → Project Settings → Plugins*).
3. Главная сцена — `scenes/world.tscn`.

## Управление

| Действие | Клавиша |
|---|---|
| Движение | W / A / S / D |
| Прыжок | Space |
| Спринт | Shift |
| Освободить мышь | Esc (клик по окну возвращает захват) |

## Структура

- `scenes/` — сцены (мир, игрок, ландшафт, UI); `scenes/terrain_data/` — данные регионов Terrain3D
- `scripts/player.gd` — контроллер игрока (движение, выносливость, эффекты камеры); все настройки задаются в его `@export`-переменных
- `scenes/ui/stat_bar.gd` — универсальная шкала (`StatBar`) для здоровья и выносливости
- `addons/` — Terrain3D и Zylann Voxel Tools (GDExtension)
- `models/`, `textures/` — ассеты

## Лицензии

Лицензии сторонних плагинов лежат в `addons/*`. Проверьте лицензии ассетов в `textures/ui_temp` и `models/nature`.
