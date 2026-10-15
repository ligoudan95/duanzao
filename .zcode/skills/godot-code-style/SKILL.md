---
name: godot-code-style
description: Use whenever writing, editing, reviewing, or reformatting GDScript (.gd) files, or answering questions about GDScript conventions — even if code style isn't explicitly mentioned. Official Godot style guide distilled into code order, naming conventions, formatting rules, static typing, and a complete file template.
---

# GDScript Code Style (official Godot style guide)

Distilled from the official Godot documentation (stable branch, checked 2026-09 — matches Godot 4.x / 4.7):

- Style guide: <https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html>
- Static typing: <https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/static_typing.html>

> **Related skills:** **gdscript-patterns** for language idioms (await, lambdas, match), **gdscript-advanced** for production depth, **godot-code-review** for the review workflow. This skill covers *how code should look and be ordered* per the official guide.

> **Precedence:** project-local style rules (naming prefixes, architecture constraints, stricter typing mandates) always override this generic guide when they conflict. When touching existing code, match the file's established style rather than reformatting it wholesale — silent mass-reformatting destroys diff history.

---

## 1. Code order

Every `.gd` file follows this layout, top to bottom:

| # | Element |
|---|---------|
| 01 | `@tool` annotation (only if the script must run in the editor) |
| 02 | `class_name` (only if the class needs global registration) |
| 03 | `extends` |
| 04 | Class docstring (`## ...`) |
| 05 | Signals |
| 06 | Enums |
| 07 | Constants |
| 08 | Static variables |
| 09 | `@export` variables |
| 10 | Remaining public variables |
| 11 | Private variables (`_` prefix) |
| 12 | `@onready` variables |
| 13 | `_static_init()` and other static methods |
| 14 | Overridden built-in virtuals, in lifecycle order: `_init`, `_enter_tree`, `_ready`, `_process`, `_physics_process`, then input/other virtuals (`_unhandled_input`, ...) |
| 15 | Overridden custom methods (from a user-defined base class) |
| 16 | Remaining public methods |
| 17 | Remaining private methods (`_` prefix) |
| 18 | Inner classes |

Guiding principles, from the official guide:

- Properties and signals come before methods.
- Public comes before private.
- Virtual callbacks come before the class's own interface.
- Construction and initialization come before runtime modifiers.

## 2. Naming conventions

| What | Convention | Example |
|------|------------|---------|
| File names | `snake_case` | `yaml_parser.gd` |
| Classes (`class_name`) | `PascalCase` | `class_name YAMLParser` |
| Node names | `PascalCase` | `Camera3D`, `Player` |
| Functions | `snake_case` | `func load_level():` |
| Variables | `snake_case` | `var particle_effect` |
| — private members | `_` prefix | `var _private_var` |
| Signals | `snake_case`, **past tense** | `signal door_opened` |
| Constants | `CONSTANT_CASE` | `const MAX_SPEED = 200` |
| Enum names | `PascalCase`, singular | `enum Element` |
| Enum members | `CONSTANT_CASE` | `EARTH, WATER, WIND, FIRE` |

## 3. Formatting rules

### Encoding
- LF line breaks, UTF-8 without BOM.

### Indentation
- **Tabs, never spaces**, for block indentation. One tab per level.
- Use spaces (never tabs) only for *alignment* of continued content.
- Continuation lines of a wrapped statement are indented **2 extra levels**.
- Exception: multiline arrays, dictionaries, and enums indent their body by only **1 extra level**.

### Trailing comma
- Multiline arrays/dicts/enums/parameter lists end with a trailing comma — cleaner diffs.

```gdscript
enum Element {
	EARTH,
	WATER,
	WIND,
	FIRE,
}

var levels: Array[String] = [
	"res://levels/forest.tscn",
	"res://levels/cave.tscn",
]
```

- Single-line lists take no trailing comma.

### Blank lines
- **Two** blank lines around functions and classes.
- **One** blank line inside a function between logical sections.

### Line length
- Keep lines under **100 characters**; ~80 is the comfortable target.

### One statement per line
- Never `if x: do_y()` on a single line. The ternary (`a if cond else b`) is the only sanctioned inline expression.

### Multiline statements
- Wrap long conditions in **parentheses**, never backslashes.
- Put `and` / `or` **at the start** of continuation lines.
- Indent the continuation 2 extra levels.

```gdscript
if (
	long_condition_one
	and long_condition_two
):
	do_something()
```

### Parentheses in conditions
- Don't wrap a single call in redundant parens:

```gdscript
# Bad
if (is_colliding()):
	...

# Good
if is_colliding():
	...
```

### Boolean operators
- Prefer the plain-English `and`, `or`, `not` over `&&`, `||`, `!`.

### Comments
- `#` and `##` comments start with a space after the hash: `# like this`.
- Prefer comments on their own line, above the code they describe.
- (`##` doc comments appear above classes and their members; they feed the editor's documentation.)

### Whitespace
- One space around operators, and after commas.
- No space before the parens of a call: `foo(1, 2)`, not `foo (1, 2)`.
- Single-line dictionaries space their braces: `{ key = "value" }`.
- Do not vertically-align assignments with runs of spaces.

### Quotes
- **Double quotes by default.** Use single quotes only when the string itself contains double quotes, to cut down on escapes.

### Numbers
- Always have digits on both sides of the dot: `0.5`, never `.5` or `5.`.
- Lowercase hex literals: `0xfb8c0b`.
- Use underscores as digit separators in large literals: `1_234_567_890`. Below one million, usually no separators.

## 4. Static typing essentials

GDScript typing is optional but recommended — it catches bugs at parse time, improves autocomplete, and speeds up code.

- **Declared type** — `var health: int = 0`, `func heal(amount: int) -> void:`
- **Inferred type** — `var health := 0`

Official guidance on which to use:

> Prefer `:=` when the type is written on the same line as the assignment (`:= 0` clearly means `int`). When the initializer doesn't reveal the type — a function call like `complex_function()`, or `get_node()` which only infers `Node` — write the type explicitly.

```gdscript
var damage := 10                      # type is obvious from the literal
var health: int = get_starting_hp()   # call result — declare the type
var bar: ProgressBar = get_node("UI/LifeBar")  # get_node only infers Node
```

Casting summary (full rules in [references/static-typing.md](references/static-typing.md)):

- `as` **silently produces `null`** on a failed cast — only use it when that is intended, and null-check afterwards.
- Prefer an `is` check followed by a typed assignment: `var player: Player = body` — a mismatch then **fails fast** at load instead of hiding as `null` deep in gameplay.
- `body is not PlayerController` works since Godot 4.

**Read [references/static-typing.md](references/static-typing.md) before doing deeper type work:** what can be a type hint, covariance/contravariance rules for overrides, typed arrays/dictionaries and their limits, "safe lines", the `absf`/`clampf`/`roundf` typed-global-functions table, and how to enable the `UNSAFE_*` / `UNTYPED_DECLARATION` warnings in Project Settings.

## 5. Complete file template

A full file in official order, with every slot demonstrated (adapted from the style guide's example):

```gdscript
@tool
class_name StateMachine
extends Node
## Forwards engine callbacks to the active child State and emits
## state_changed on every transition. The first State child starts active.

signal state_changed(current_state: State)

enum TransitionMode {
	ALLOW_REPEAT,
	NO_REPEAT,
}

const GROUP_NAME: StringName = &"state_machine"

static var transition_count: int = 0

@export var transition_mode: TransitionMode = TransitionMode.ALLOW_REPEAT
@export var autostart: bool = true

var is_active: bool = true:
	set = set_is_active

@onready var current_state: State = get_child(0) as State


static func describe() -> String:
	return "StateMachine, %d lifetime transitions" % transition_count


func _init() -> void:
	add_to_group(GROUP_NAME)


func _ready() -> void:
	if autostart:
		current_state.enter()


func _unhandled_input(event: InputEvent) -> void:
	current_state.handle_input(event)


func _physics_process(delta: float) -> void:
	if is_active:
		current_state.update(delta)


func transition_to(target_state_name: StringName) -> void:
	if not has_node(target_state_name):
		push_error("Unknown state: %s" % target_state_name)
		return
	var target_state: State = get_node(target_state_name) as State
	if target_state == current_state and transition_mode == TransitionMode.NO_REPEAT:
		return
	current_state.exit()
	current_state = target_state
	transition_count += 1
	current_state.enter()
	state_changed.emit(current_state)


func set_is_active(value: bool) -> void:
	is_active = value
	set_physics_process(value)


class State:
	## Base class for states. Extend and override the callbacks you need.
	var times_entered: int = 0

	func enter() -> void:
		times_entered += 1

	func exit() -> void:
		pass

	func update(_delta: float) -> void:
		pass

	func handle_input(_event: InputEvent) -> void:
		pass
```

## 6. Review checklist

- [ ] File layout follows the code order table (§1)
- [ ] Names follow the conventions table (§2) — signals in past tense, constants `CONSTANT_CASE`
- [ ] Tabs for indentation; spaces only for alignment
- [ ] Double quotes by default
- [ ] `and` / `or` / `not`, not `&&` / `||` / `!`
- [ ] One statement per line; wrapped conditions in parentheses with the operator leading
- [ ] Lines under 100 characters
- [ ] Trailing commas on multiline collections; none on single-line
- [ ] Two blank lines around functions, one inside between sections
- [ ] `:=` only when the same-line initializer makes the type obvious; explicit `: Type` otherwise
- [ ] `as` casts are null-checked; prefer `is` + typed assignment for failure-critical casts
- [ ] Numbers fully qualified (`0.5` not `.5`), lowercase hex, separators on large literals
