# Static Typing in GDScript — Full Reference

Deep-dive companion to the main skill file. Source: the official
[Static typing in GDScript](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/static_typing.html)
page (stable branch, checked 2026-09).

## 1. What can be used as a type hint

1. **`Variant`** — accepts any type. Behaves mostly like an untyped variable, but reads as an explicit "anything goes" declaration; as a **return type it forces the function to explicitly return some value**.
2. **`void`** — return type only: the function returns nothing.
3. **Built-in types** — `int`, `float`, `String`, `Vector2`, `bool`, ...
4. **Native classes** — `Object`, `Node`, `Area2D`, `Camera2D`, `Timer`, ...
5. **Global classes** — anything registered with `class_name`.
6. **Inner classes** — classes declared inside another script.
7. **Named enums** (global, native, or custom) — an enum type is just an `int`; the compiler does *not* guarantee the value belongs to the enum's set.
8. **Constants** holding a preloaded class or an enum — `const Rifle = preload("res://weapon/rifle.gd")` then `var weapon: Rifle`.

## 2. Cases where you CANNOT specify types (syntax errors)

No per-element types inside array/dictionary literals:

```gdscript
# Both are INVALID syntax:
var enemies: Array = [$Goblin: Enemy, $Zombie: Enemy]
var character: Dictionary = {
	name: String = "Richard",
	money: int = 1000,
}
```

No nested typed collections:

```gdscript
var teams: Array[Array[Character]] = []  # INVALID
```

## 3. Function return types

```gdscript
func _process(delta: float) -> void:
	pass

func add(item: Item, amount: int = 1) -> Item:
	return item
```

- Anything usable as a variable type works as a return type, including your own classes.
- `void` = returns nothing.
- `Variant` as a return type forces an explicit `return` statement.
- Typed parameters with default values are fine (`amount: int = 1` above).

## 4. Type casting: `as` vs `is`

### `as` — cast, silently `null` on mismatch

```gdscript
func _on_body_entered(body: PhysicsBody2D) -> void:
	var player := body as PlayerController
	if not player:
		return
	player.damage()
```

`as` **silently produces `null`** if the runtime type doesn't match — use it only when a `null` fallback is intended, and null-check the result. (A failed `as` cast between *built-in* types throws an error instead.)

### `is` — check, then assign (fails fast — preferred)

```gdscript
if body is not PlayerController:
	push_error("Bug: body is not PlayerController.")

var player: PlayerController = body
if not player:
	return
player.damage()
```

A typed assignment `var player: PlayerController = body` **errors immediately at scene load** on a real mismatch — earlier and more reliable than a silent `null` surfacing later in gameplay. `assert` also works for invariant checks:

```gdscript
assert(body is PlayerController, "Bug: body is not PlayerController.")
```

## 5. Safe lines

The editor greys lines it cannot prove type-safe (e.g. `var timer = $Timer` — the engine can't statically know the node's class). Annotate the expected type to make the line safe:

```gdscript
@onready var timer: Timer = $Timer
var node_1 := $Node1 as Type1
```

**Safe does not mean better.** The safe `node_1` above turns into a silent `null` on mismatch, while the "unsafe-looking" typed assignment below fails immediately when the scene loads:

```gdscript
var node_2: Type2 = $Node2  # fails at load time — earlier, more reliable error
```

## 6. Covariance and contravariance (overriding typed methods)

Overridden methods must obey the Liskov substitution principle:

- **Covariance** — the override's *return type* may be a **subtype** of the parent's.
- **Contravariance** — the override's *parameter type* may be a **supertype** of the parent's.

```gdscript
# Parent
func get_property(param: Label) -> Node:
	return null

# Child — legal override: param widened, return narrowed
func get_property(param: Control) -> Node2D:
	return null
```

## 7. Typed arrays and dictionaries

```gdscript
var scores: Array[int] = [10, 20, 30]
var fruit_costs: Dictionary[String, int] = { "apple": 5, "banana": 10 }
```

What the element types actually check:

- ✔ `for` loop variables (`for score: int in scores:` — typed loop vars since Godot 4.2), indexing `[i]`, indexed assignment `[i] = x`, concatenation `+`
- ✘ method calls (`push_back`, ...) and `==` comparison remain **untyped**

Element types can be built-in types, native/custom classes, or enums. Nested typed collections are not supported. The same rules apply to typed dictionary keys/values.

## 8. Global functions with typed alternatives

Prefer the typed form — the untyped versions take/return `Variant` and skip compile-time checks:

| Untyped | Typed equivalents |
|---|---|
| `abs()` | `absf()`, `absi()`, `Vector2/2i/3/3i/4/4i.abs()` |
| `ceil()` | `ceilf()`, `ceili()`, `Vector2/3/4.ceil()` |
| `clamp()` | `clampf()`, `clampi()`, `Vector2/2i/3/3i/4/4i.clamp()`, `Color.clamp()` (untyped `clamp()` does not work on Color) |
| `floor()` | `floorf()`, `floori()`, `Vector2/3/4.floor()` |
| `lerp()` | `lerpf()`, `Vector2/3/4.lerp()`, `Color.lerp()`, `Quaternion.slerp()`, `Basis.slerp()`, `Transform2D/3D.interpolate_with()` |
| `round()` | `roundf()`, `roundi()`, `Vector2/3/4.round()` |
| `sign()` | `signf()`, `signi()`, `Vector2/2i/3/3i/4/4i.sign()` |
| `snapped()` | `snappedf()`, `snappedi()`, `Vector2/2i/3/3i/4/4i.snapped()` |

## 9. Warnings and strict mode

Relevant GDScript warnings (Project Settings → **Debug → GDScript**, turn on **Advanced Settings** — these are off by default):

| Warning | Meaning |
|---|---|
| `UNTYPED_DECLARATION` | A variable/parameter lacks a type — enable to enforce always-typed code |
| `INFERRED_DECLARATION` | Uses `:=` — enable to force explicit `: Type` |
| `UNSAFE_PROPERTY_ACCESS` | Property access the compiler can't verify |
| `UNSAFE_METHOD_ACCESS` | Method call the compiler can't verify |
| `UNSAFE_CAST` | An `as` cast it can't prove safe |
| other `UNSAFE_*` | Related unsafe-operation warnings |

Each warning can be set to Ignore / Warn / Error — set to **Error** for strict team enforcement.

Caveats:

- `UNSAFE_*` warnings do **not** cover every case that unsafe lines flag — green lines and zero warnings are not a full proof of type safety.
- Checking membership dynamically (`if node_2d.has_method("fly"):` or `if "x" in obj:`) still leaves subsequent accesses flagged; resolve with `is` + a typed variable, or an `as` cast + null check.
