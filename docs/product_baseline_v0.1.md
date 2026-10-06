Codebase Map — v0.1 Product Baseline
1. Что это вообще такое
Codebase Map — кроссплатформенное desktop-приложение для визуального исследования структуры программного проекта.
Главная проблема, которую оно решает:
Я открыл незнакомый или давно забытый проект. Какие здесь основные части и как они связаны друг с другом?

Вместо исследования десятков папок и постоянных переходов по import пользователь получает интерактивную карту codebase.
Например:
                         main.dart
                            │
                  ┌─────────┴─────────┐
                  ▼                   ▼
               app.dart          bootstrap.dart
                  │
          ┌───────┴────────┐
          ▼                ▼
       router.dart      theme.dart
          │
     ┌────┴─────┐
     ▼          ▼
   home/      settings/
     │
     ▼
 repository.dart
     │
     ▼
 api_client.dart

Это не редактор кода и не IDE.
Это инструмент понимания codebase.
2. Целевая первая версия
Для v0.1 поддерживаем только:
Dart / Flutter projects
но внутреннюю архитектуру строим так, чтобы позднее можно было подключить:
LanguageAnalyzer
      │
      ├── DartAnalyzer
      ├── TypeScriptAnalyzer     ← потом
      ├── PythonAnalyzer         ← потом
      └── ...

Не надо реализовывать эти интерфейсы раньше времени, если они сейчас не нужны. Важно просто не привязать всё приложение намертво к Dart.
Платформы:
macOS + Windows + Linux.
3. Основной пользовательский сценарий
После запуска пользователь видит простой стартовый экран:
CODEBASE MAP

Understand your project.

        [ Open Project ]

Recent projects
────────────────
○ my_flutter_app
○ codebase_map

Нажимает:
Open Project
и выбирает локальную папку.
Codebase Map определяет, что это Dart/Flutter-проект, сканирует его и строит карту.
4. Что анализируем
Не нужно отображать вообще всё содержимое проекта.
Например:
.git/
.dart_tool/
build/
.idea/
macos/
windows/
linux/
assets/

для первоначального понимания Dart-кода в основном являются шумом.
Основная область v0.1:
lib/

Дополнительно можно анализировать test/, но пользователь должен иметь возможность его скрыть.
Программа должна понимать как минимум:
import 'package:codebase_map/core/foo.dart';
import '../models/bar.dart';

export 'scanner.dart';

part 'something.g.dart';
part of 'something.dart';

А внешняя зависимость вроде:
import 'package:flutter/material.dart';

не должна превращать карту нашего проекта в гигантское дерево исходников Flutter SDK.
5. Главный экран
После анализа интерфейс примерно такой:
┌───────────────────────────────────────────────────────────────┐
│ Codebase Map │ my_project                         🔍 Search   │
├──────────────┬───────────────────────────────┬────────────────┤
│              │                               │                │
│ PROJECT      │       DEPENDENCY MAP          │ FILE DETAILS   │
│              │                               │                │
│ lib/         │       ┌───────────┐           │ app.dart       │
│ ├ core/      │       │ main.dart │           │                │
│ ├ features/  │       └─────┬─────┘           │ Imports: 5     │
│ └ main.dart  │             │                 │ Imported by: 2 │
│              │       ┌─────▼─────┐           │                │
│              │       │ app.dart  │           │ Path           │
│              │       └───────────┘           │ lib/app.dart   │
│              │                               │                │
└──────────────┴───────────────────────────────┴────────────────┘

То есть три ключевые области:
Project Tree | Graph | Inspector
6. Интерактивная карта
Это сердце приложения.
Каждый локальный Dart-файл — node.
Зависимость — edge.
Например:
// home_page.dart

import '../services/user_service.dart';

превращается в:
home_page.dart ─────→ user_service.dart

Пользователь должен уметь:
- перемещать карту;
- zoom in/out;
- выбирать узлы;
- перемещать отдельные узлы;
- центрировать карту;
- возвращаться к Fit to screen.
Для больших проектов это принципиально.
7. Навигация между Tree и Graph
Вот здесь уже появляется настоящая полезность.
Нажимаю:
lib/features/auth/login_page.dart

в Project Tree.
На карте автоматически находится и выделяется соответствующий node.
И наоборот: нажимаю node на графе → файл выделяется в дереве и открывается Inspector.
Получается единая модель:
Project Tree
      ↕
Dependency Graph
      ↕
Inspector

8. Inspector
При выборе файла справа показываем хотя бы:
login_page.dart

PATH
lib/features/auth/login_page.dart

DEPENDENCIES
→ auth_service.dart
→ login_state.dart
→ validators.dart

USED BY
← router.dart
← auth_module.dart

STATISTICS
Imports:       3
Imported by:   2
Lines:       184

И уже здесь Codebase Map начинает отвечать на полезные вопросы:
«От чего зависит этот файл?»
и
«Что зависит от него?»
9. Focus Mode
Я бы обязательно включил это уже в v0.1.
На огромной карте выбираешь:
auth_service.dart

и нажимаешь:
Focus
Всё лишнее временно исчезает:
                api_client.dart
                      ↑
                      │
login_page.dart → auth_service.dart ← register_page.dart
                      │
                      ▼
                token_store.dart

Показываем выбранный файл + непосредственные входящие и исходящие зависимости.
Это может оказаться одной из самых полезных функций всего приложения.
10. Поиск
Для проекта из 500 файлов визуально искать node бессмысленно.
Поэтому:
Search files...

auth

результат:
auth_service.dart
auth_repository.dart
auth_state.dart
auth_page.dart

Клик → карта автоматически перемещается к соответствующему node.
11. Фильтры
Минимум:
☑ lib
☐ test
☑ Generated files

Dependencies:
☑ imports
☑ exports
☑ parts

Особенно generated files.
В Flutter-проекте всякие:
*.g.dart
*.freezed.dart

способны сильно засорить карту.
12. Обработка проблем
Codebase Map не должен падать от странного проекта.
Например, нашли:
import 'something_that_does_not_exist.dart';

Показываем:
⚠ 3 unresolved dependencies

а не ломаем весь анализ.
Аналогично должны нормально переживаться:
- недоступные файлы;
- symlink;
- циклические зависимости;
- пустой lib;
- не-Dart проект;
- повреждённый pubspec.yaml.
13. Что специально НЕ входит в v0.1
Это очень важно зафиксировать.
Не делаем пока:
AI-анализ архитектуры, Git history, GitHub integration, редактирование кода, встроенный editor, terminal, refactoring, UML, class-level graph, function call graph, TypeScript/Python/Java/Kotlin, backend, аккаунты, cloud sync, collaboration.
Иначе MVP никогда не закончится.
14. Что будет означать «v0.1 готова»
Вот наш настоящий acceptance test.
Берём Codebase Map и открываем в Codebase Map сам Codebase Map.
Программа должна:
Codebase Map
      ↓
Open Project
      ↓
codebase_map/
      ↓
Scan
      ↓
Recognize Dart/Flutter
      ↓
Analyze lib/
      ↓
Resolve dependencies
      ↓
Build graph
      ↓
Render graph

После этого мы должны иметь возможность найти:
main.dart

выбрать его → посмотреть зависимости → перейти по ним → включить Focus Mode → вернуться ко всей карте.