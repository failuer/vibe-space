# Real-Time Firing + Code Restructure — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the game monolith into logic + renderer files, then add a real-time fire button for the player (with ammo + cooldown) and autonomous firing for enemy ships during simulation.

**Architecture:** `game.gd` owns all state and logic; `game_renderer.gd` (child Node2D) reads state via `get_parent()` and does all drawing. A `FireButton` + `CooldownFill` + `AmmoDisplay` live in the existing `CanvasLayer`. Enemies gain per-instance ammo and cooldown tracked in their dictionaries.

**Tech Stack:** Godot 4.5, GDScript. No automated test framework — verification is done by running the game in the Godot editor and observing behaviour. Each task ends with a in-editor run check and a git commit.

**Beads issues:** vibe-space-pqn (firing), vibe-space-a8l (refactor)

**Spec:** `docs/superpowers/specs/2026-03-22-realtime-firing-design.md`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Rename | `new_script.gd` → `game.gd` | All game logic, state, input, simulation, AI |
| Create | `game_renderer.gd` | All `_draw*` functions; reads `Game` parent, never writes |
| Create | `ammo_display.gd` | Custom `Control` that draws missile-glyph ammo indicators |
| Rename | `node_2d.tscn` → `game_world.tscn` | Main scene; gains Renderer child node + fire button UI |

---

## Task 1: Rename files and fix scene references

**Files:**
- Rename: `new_script.gd` → `game.gd`
- Rename: `node_2d.tscn` → `game_world.tscn`
- Modify: `game.gd` (add `class_name`)
- Modify: `game_world.tscn` (update script path)
- Modify: `project.godot` (update main scene path)

- [ ] **Step 1: Rename the script file**

```bash
cd /Users/kask/Repos/vibe-space
mv new_script.gd game.gd
```

- [ ] **Step 2: Add `class_name Game` to the top of `game.gd`**

Open `game.gd`. After the first line (`extends Node2D`), add:

```gdscript
extends Node2D
class_name Game
```

Also delete the `new_script.gd.uid` file — Godot will regenerate it:

```bash
rm new_script.gd.uid
```

- [ ] **Step 3: Rename the scene file**

```bash
mv node_2d.tscn game_world.tscn
```

- [ ] **Step 4: Update the script path inside `game_world.tscn`**

Open `game_world.tscn`. Find the `ext_resource` line that references `new_script.gd` and change the path:

```
# Before:
[ext_resource type="Script" uid="uid://b05ahhjv38rm1" path="res://new_script.gd" id="1_wtcfe"]

# After:
[ext_resource type="Script" uid="uid://b05ahhjv38rm1" path="res://game.gd" id="1_wtcfe"]
```

- [ ] **Step 5: Update `project.godot` to point at the renamed scene**

Open `project.godot`. Find:

```
run/main_scene="res://node_2d.tscn"
```

Change to:

```
run/main_scene="res://game_world.tscn"
```

- [ ] **Step 6: Run the game in the Godot editor**

Open the project in Godot 4.5, press F5 (or the Play button). The game should run exactly as before — three enemies, planning phase, stars, everything. If you get a "script not found" error, re-check the path in `game_world.tscn`.

- [ ] **Step 7: Commit**

```bash
git add game.gd game_world.tscn project.godot .gitignore
git rm new_script.gd new_script.gd.uid node_2d.tscn
git commit -m "refactor: rename new_script.gd -> game.gd, node_2d.tscn -> game_world.tscn"
```

---

## Task 2: Extract renderer into `game_renderer.gd`

**Files:**
- Modify: `game.gd` (remove all `_draw*` functions, remove `planned_end_pos` var, keep `_arc_endpoint`)
- Create: `game_renderer.gd`
- Modify: `game_world.tscn` (add child `Renderer` Node2D with `game_renderer.gd` script)

**Important:** `_arc_endpoint()` stays in `game.gd` — it is used by `_update_planned_vector()` (logic) and will be called by the renderer via `game._arc_endpoint(...)`.

- [ ] **Step 1: Create `game_renderer.gd`**

Create `/Users/kask/Repos/vibe-space/game_renderer.gd` with this content:

```gdscript
extends Node2D

var game: Game

func _ready() -> void:
    game = get_parent() as Game

func _draw() -> void:
    _draw_starfield()
    _draw_outside_dark_mask()
    _draw_play_area_inner_border()

    if game.player_alive:
        _draw_circle_outline(game.player_pos, game.PLAYER_RADIUS, game.PLAYER_COLOR)

    for enemy in game.enemies:
        if enemy.alive:
            _draw_circle_outline(enemy.pos, game.ENEMY_RADIUS, game.ENEMY_COLOR)

    for missile in game.missiles:
        var col: Color = game.MISSILE_COLOR
        if not missile.from_player:
            col = game.ENEMY_MISSILE_COLOR
        _draw_circle_outline(missile.pos, game.MISSILE_RADIUS, col)

    if game.phase == Game.GamePhase.PLANNING and game.player_alive:
        _draw_turn_wedge()
        _draw_planned_path()
        _draw_planned_ghost()


func _draw_circle_outline(center: Vector2, radius: float, color: Color) -> void:
    var points := 32
    var angle_step := TAU / float(points)
    for i in points:
        var a := angle_step * i
        var b := angle_step * (i + 1)
        var p1 := center + Vector2(cos(a), sin(a)) * radius
        var p2 := center + Vector2(cos(b), sin(b)) * radius
        draw_line(p1, p2, color, 1.5)


func _draw_play_area_inner_border() -> void:
    var r := game._play_area_rect()
    var t := game.PLAY_BORDER_THICKNESS

    draw_rect(Rect2(r.position, Vector2(r.size.x, t)), game.BORDER_COLOR, true)
    draw_rect(Rect2(Vector2(r.position.x, r.position.y + r.size.y - t), Vector2(r.size.x, t)), game.BORDER_COLOR, true)
    draw_rect(Rect2(r.position, Vector2(t, r.size.y)), game.BORDER_COLOR, true)
    draw_rect(Rect2(Vector2(r.position.x + r.size.x - t, r.position.y), Vector2(t, r.size.y)), game.BORDER_COLOR, true)


func _draw_outside_dark_mask() -> void:
    var r := game._play_area_rect()
    var dark_color := Color(0.0, 0.0, 0.0, 0.9)
    var big_size := r.size * 4.0
    var big_origin := -big_size * 0.5

    draw_rect(Rect2(big_origin, Vector2(big_size.x, r.position.y - big_origin.y)), dark_color, true)
    var bottom_y := r.position.y + r.size.y
    var bottom_height := big_origin.y + big_size.y - bottom_y
    draw_rect(Rect2(Vector2(big_origin.x, bottom_y), Vector2(big_size.x, bottom_height)), dark_color, true)
    draw_rect(Rect2(Vector2(big_origin.x, r.position.y), Vector2(r.position.x - big_origin.x, r.size.y)), dark_color, true)
    var right_x := r.position.x + r.size.x
    var right_width := big_origin.x + big_size.x - right_x
    draw_rect(Rect2(Vector2(right_x, r.position.y), Vector2(right_width, r.size.y)), dark_color, true)


func _draw_starfield() -> void:
    for layer_idx in game.STAR_LAYER_COUNT:
        var stars: Array = game._stars_by_layer[layer_idx]
        var parallax: float = float(game.STAR_PARALLAX_BY_LAYER[layer_idx])
        var radius: float = float(game.STAR_RADIUS_BY_LAYER[layer_idx])

        var shift := game.player_pos * parallax
        var shift_mod := Vector2(
            fposmod(shift.x, game.STAR_TILE_SIZE.x),
            fposmod(shift.y, game.STAR_TILE_SIZE.y)
        )

        for oy in [-1, 0, 1]:
            for ox in [-1, 0, 1]:
                var tile_offset := Vector2(float(ox) * game.STAR_TILE_SIZE.x, float(oy) * game.STAR_TILE_SIZE.y)
                for s: Vector2 in stars:
                    var screen_pos: Vector2 = s + tile_offset - shift_mod
                    var world_pos: Vector2 = game.player_pos + screen_pos
                    draw_circle(world_pos, radius, game.STAR_COLOR)


func _draw_planned_path() -> void:
    var steps := 18
    var dt := game.SIM_DURATION / float(steps)

    var preview_pos := game.player_pos
    var preview_vel := game.player_vel
    var preview_speed := game.planned_player_speed
    var preview_turn_rate: float = 0.0
    if game.SIM_DURATION > 0.0:
        preview_turn_rate = game.planned_turn_angle / game.SIM_DURATION

    var prev := preview_pos
    for i in steps:
        var step_angle := preview_turn_rate * dt
        if step_angle != 0.0:
            preview_vel = preview_vel.rotated(step_angle)
        preview_vel = preview_vel.normalized() * preview_speed
        preview_pos += preview_vel * dt
        draw_line(prev, preview_pos, game.PLANNED_VECTOR_COLOR, 2.0)
        prev = preview_pos


func _draw_planned_ghost() -> void:
    var col := game.PLAYER_COLOR
    col.a = 0.35
    var end_pos := game._arc_endpoint(game.player_pos, game.player_vel.normalized(), game.planned_player_speed, game.planned_turn_angle)
    _draw_circle_outline(end_pos, game.PLAYER_RADIUS, col)


func _draw_turn_wedge() -> void:
    var forward_dir := game.player_vel.normalized()
    if forward_dir == Vector2.ZERO:
        forward_dir = Vector2.UP

    var segments: int = 40
    var col := game.PLANNED_VECTOR_COLOR
    col.a = 0.25

    var outer_pts: Array[Vector2] = []
    for i in range(segments + 1):
        var t := float(i) / float(segments)
        var ang := -game.turn_limit_this_turn + 2.0 * game.turn_limit_this_turn * t
        outer_pts.append(game._arc_endpoint(game.player_pos, forward_dir, game.PLAYER_SPEED_MAX, ang))

    var inner_pts: Array[Vector2] = []
    for i in range(segments + 1):
        var t := float(i) / float(segments)
        var ang := game.turn_limit_this_turn - 2.0 * game.turn_limit_this_turn * t
        inner_pts.append(game._arc_endpoint(game.player_pos, forward_dir, game.PLAYER_SPEED_MIN, ang))

    for i in range(outer_pts.size() - 1):
        draw_line(outer_pts[i], outer_pts[i + 1], col, 1.0)
    for i in range(inner_pts.size() - 1):
        draw_line(inner_pts[i], inner_pts[i + 1], col, 1.0)

    draw_line(outer_pts[0], inner_pts[inner_pts.size() - 1], col, 1.0)
    draw_line(outer_pts[outer_pts.size() - 1], inner_pts[0], col, 1.0)
```

- [ ] **Step 2: Remove all `_draw*` functions and `_draw()` from `game.gd`**

In `game.gd`, delete the following functions entirely:
- `_draw()`
- `_draw_circle_outline()`
- `_draw_play_area_inner_border()`
- `_draw_outside_dark_mask()`
- `_draw_starfield()`
- `_draw_planned_path()`
- `_draw_planned_ghost()`
- `_draw_turn_wedge()`

Also remove the `planned_end_pos` variable declaration — it was a side-effect of `_draw_planned_path()` and is no longer needed.

- [ ] **Step 3: Add `queue_redraw()` call for the renderer in `_process`**

In `game.gd`, the existing `_process` ends with `queue_redraw()`. Replace that with a call that triggers the renderer's redraw instead:

```gdscript
func _process(delta: float) -> void:
    if phase == GamePhase.SIMULATING:
        _step_simulation(delta)
    elif phase == GamePhase.ENDED:
        _step_end_timer(delta)

    camera.position = player_pos
    $Renderer.queue_redraw()
```

- [ ] **Step 4: Add the `Renderer` child node to `game_world.tscn`**

Open `game_world.tscn` in a text editor. Add the following lines — a new `ext_resource` for the renderer script, and a new node entry as a child of the root:

At the top, after the existing `ext_resource` line, add:
```
[ext_resource type="Script" path="res://game_renderer.gd" id="2_renderer"]
```

After the `[node name="Game" ...]` block, add:
```
[node name="Renderer" type="Node2D" parent="."]
script = ExtResource("2_renderer")
```

- [ ] **Step 5: Run the game**

Press F5. The game should render identically to before — starfield, ships, wedge, ghost. If the screen is blank or you see errors about missing members, check that all constants/vars accessed in `game_renderer.gd` are not local-only in `game.gd` (they should all be at the class level already).

- [ ] **Step 6: Commit**

```bash
git add game.gd game_renderer.gd game_world.tscn
git commit -m "refactor: extract rendering into game_renderer.gd child node"
```

---

## Task 3: Add ammo and cooldown data model

**Files:**
- Modify: `game.gd` (new constants, new player vars, updated enemy dict, cooldown ticking)

- [ ] **Step 1: Add weapon constants to `game.gd`**

After the existing constants block (after `_compute_turn_limit_for_speed` related constants), add:

```gdscript
const PLAYER_MAX_MISSILES := 10
const PLAYER_FIRE_COOLDOWN := 4.0

const ENEMY_MAX_MISSILES := 6
const ENEMY_FIRE_COOLDOWN := 3.5
const ENEMY_FIRE_ANGLE_THRESHOLD := PI / 4.0  # 45 degrees
```

- [ ] **Step 2: Add player weapon state variables**

After the existing player state vars block, add:

```gdscript
var player_missiles_remaining: int = PLAYER_MAX_MISSILES
var player_fire_cooldown: float = 0.0
```

- [ ] **Step 3: Update `_reset_game()` to initialise new state**

In `_reset_game()`, after `player_alive = true`, add:

```gdscript
player_missiles_remaining = PLAYER_MAX_MISSILES
player_fire_cooldown = 0.0
```

Update each enemy dict in `_reset_game()` to include the new fields. Change all three `enemies.append({...})` calls to include:

```gdscript
enemies.append({
    "pos": Vector2(300.0, 0.0),
    "vel": Vector2.LEFT * ENEMY_SPEED,
    "alive": true,
    "missiles_remaining": ENEMY_MAX_MISSILES,
    "fire_cooldown": 0.0,
})
```
(Apply the same two new keys to the other two enemies.)

- [ ] **Step 4: Tick cooldowns every frame in `_step_simulation`**

In `_step_simulation`, after calling `_integrate_motion(delta)`, add:

```gdscript
# Tick weapon cooldowns
if player_fire_cooldown > 0.0:
    player_fire_cooldown = maxf(0.0, player_fire_cooldown - delta)
for enemy in enemies:
    if enemy.alive and enemy.fire_cooldown > 0.0:
        enemy.fire_cooldown = maxf(0.0, enemy.fire_cooldown - delta)
```

- [ ] **Step 5: Run the game**

Press F5. Behaviour should be unchanged — the new vars exist but nothing fires yet.

- [ ] **Step 6: Commit**

```bash
git add game.gd
git commit -m "feat: add ammo and cooldown data model for player and enemies"
```

---

## Task 4: Add fire button UI to the scene

**Files:**
- Create: `ammo_display.gd`
- Modify: `game_world.tscn` (add UI nodes to CanvasLayer)
- Modify: `game.gd` (`@onready` vars for new UI nodes)

- [ ] **Step 1: Create `ammo_display.gd`**

Create `/Users/kask/Repos/vibe-space/ammo_display.gd`:

```gdscript
extends Control

var missiles_remaining: int = 10
var missiles_max: int = 10

func _draw() -> void:
    var dot_radius := 6.0
    var gap := 7.0
    var step := dot_radius * 2.0 + gap
    var total_width := missiles_max * step - gap
    var start_x := (size.x - total_width) * 0.5
    var cy := size.y * 0.5

    for i in missiles_max:
        var cx := start_x + i * step + dot_radius
        var alpha := 1.0 if i < missiles_remaining else 0.22
        var color := Color(1.0, 1.0, 0.4, alpha)
        _draw_missile_glyph(Vector2(cx, cy), dot_radius, color)


func _draw_missile_glyph(center: Vector2, radius: float, color: Color) -> void:
    var points := 16
    var angle_step := TAU / float(points)
    for i in points:
        var a := angle_step * i
        var b := angle_step * (i + 1)
        draw_line(
            center + Vector2(cos(a), sin(a)) * radius,
            center + Vector2(cos(b), sin(b)) * radius,
            color, 1.5
        )
```

- [ ] **Step 2: Add fire button nodes to `game_world.tscn`**

Open `game_world.tscn`. Add the `ammo_display.gd` ext_resource reference and four new nodes inside `CanvasLayer`:

Add to the ext_resource block at the top:
```
[ext_resource type="Script" path="res://ammo_display.gd" id="3_ammo"]
```

Add these nodes (after the RestartButton node):

```
[node name="FireButtonContainer" type="VBoxContainer" parent="CanvasLayer"]
anchor_left = 0.5
anchor_top = 1.0
anchor_right = 0.5
anchor_bottom = 1.0
offset_left = -90.0
offset_right = 90.0
offset_top = -110.0
offset_bottom = -20.0
theme_override_constants/separation = 6

[node name="FireButton" type="Button" parent="CanvasLayer/FireButtonContainer"]
clip_contents = true
custom_minimum_size = Vector2(180, 44)
text = "FIRE"

[node name="CooldownFill" type="ColorRect" parent="CanvasLayer/FireButtonContainer/FireButton"]
mouse_filter = 2
color = Color(0.302, 0.91, 1, 0.13)
anchors_preset = -1
anchor_right = 0.0
anchor_bottom = 1.0
offset_right = 0.0

[node name="AmmoDisplay" type="Control" parent="CanvasLayer/FireButtonContainer"]
custom_minimum_size = Vector2(180, 20)
script = ExtResource("3_ammo")
```

- [ ] **Step 3: Add `@onready` vars to `game.gd`**

In `game.gd`, after the existing `@onready` block, add:

```gdscript
@onready var fire_button: Button = $CanvasLayer/FireButtonContainer/FireButton
@onready var cooldown_fill: ColorRect = $CanvasLayer/FireButtonContainer/FireButton/CooldownFill
@onready var ammo_display: Control = $CanvasLayer/FireButtonContainer/AmmoDisplay
```

- [ ] **Step 4: Style `FireButton` with a pill StyleBoxFlat at runtime**

In `game.gd`'s `_ready()`, after `restart_button.pressed.connect(...)`, add:

```gdscript
var style := StyleBoxFlat.new()
style.bg_color = Color(0, 0, 0, 0)
style.border_width_left = 2
style.border_width_right = 2
style.border_width_top = 2
style.border_width_bottom = 2
style.border_color = Color(0.3, 0.91, 1.0, 1.0)
style.corner_radius_top_left = 22
style.corner_radius_top_right = 22
style.corner_radius_bottom_left = 22
style.corner_radius_bottom_right = 22
fire_button.add_theme_stylebox_override("normal", style)
fire_button.add_theme_stylebox_override("hover", style)
fire_button.add_theme_stylebox_override("pressed", style)
fire_button.add_theme_stylebox_override("disabled", style)
fire_button.add_theme_color_override("font_color", Color(0.3, 0.91, 1.0))
fire_button.add_theme_color_override("font_disabled_color", Color(0.3, 0.91, 1.0, 0.3))

ammo_display.missiles_max = PLAYER_MAX_MISSILES
ammo_display.missiles_remaining = player_missiles_remaining
```

- [ ] **Step 5: Run the game**

Press F5. You should see the fire button appear at the bottom-centre of the screen with the pill border and ammo dots below it. Nothing is wired yet — clicking does nothing.

- [ ] **Step 6: Commit**

```bash
git add game.gd game_world.tscn ammo_display.gd
git commit -m "feat: add fire button UI with cooldown fill and ammo display"
```

---

## Task 5: Implement player firing

**Files:**
- Modify: `game.gd` (fire logic, remove `planned_fire`, update UI each frame)

- [ ] **Step 1: Remove `planned_fire`**

In `game.gd`:
- Delete the variable declaration: `var planned_fire: bool = false`
- Delete `planned_fire = false` from `_reset_game()`
- Delete the `planned_fire = false` reset at the end of `_start_simulation()`
- Delete the `if planned_fire and player_alive:` missile-spawn block in `_start_simulation()` — this will be replaced below
- Delete the `elif event is InputEventMouseButton and event.pressed:` block that toggled `planned_fire` in `_unhandled_input()`

Then grep for any remaining references to be safe:
```bash
grep -n "planned_fire" game.gd
```
Expected: no output. If any remain, delete them.

**Note:** The spec described planning-phase fire as "queue a shot for sim-start." The plan simplifies this to immediate firing in both phases — same result, simpler code, better UX (the shot flies as soon as you click, not delayed until you commit).

- [ ] **Step 2: Add `_try_fire_player()` and connect the button**

In `game.gd`, add this function (before `_update_planned_vector`):

```gdscript
func _try_fire_player() -> void:
    if not player_alive:
        return
    if player_missiles_remaining <= 0:
        return
    if player_fire_cooldown > 0.0:
        return

    var dir := player_vel.normalized()
    var spawn_pos := player_pos + dir * (PLAYER_RADIUS + MISSILE_RADIUS + 2.0)
    missiles.append({
        "pos": spawn_pos,
        "vel": dir * MISSILE_SPEED,
        "from_player": true,
    })
    player_missiles_remaining -= 1
    player_fire_cooldown = PLAYER_FIRE_COOLDOWN
```

In `_ready()`, after the restart_button connection, add:

```gdscript
fire_button.pressed.connect(_try_fire_player)
```

- [ ] **Step 3: Gate the fire button correctly**

The button should be disabled when `player_fire_cooldown > 0` or `missiles_remaining == 0` or `phase == ENDED`. Add a `_update_fire_button_ui()` function:

```gdscript
func _update_fire_button_ui() -> void:
    var ready := player_fire_cooldown <= 0.0 and player_missiles_remaining > 0 and phase != GamePhase.ENDED

    fire_button.disabled = not ready

    if player_missiles_remaining <= 0:
        fire_button.text = "NO AMMO"
    elif player_fire_cooldown > 0.0:
        fire_button.text = "RELOADING..."
    else:
        fire_button.text = "FIRE"

    # Cooldown fill: sweeps left-to-right as cooldown expires (0 = just fired, full = ready)
    var fill_ratio := 1.0 - clampf(player_fire_cooldown / PLAYER_FIRE_COOLDOWN, 0.0, 1.0)
    cooldown_fill.size.x = fire_button.size.x * fill_ratio

    # Fade border to 25% opacity when out of ammo
    var border_alpha := 0.25 if player_missiles_remaining <= 0 else 1.0
    var s := fire_button.get_theme_stylebox("normal") as StyleBoxFlat
    if s:
        s.border_color = Color(0.3, 0.91, 1.0, border_alpha)

    # Ammo dots
    ammo_display.missiles_remaining = player_missiles_remaining
    ammo_display.queue_redraw()
```

Call it at the end of `_process()`:

```gdscript
func _process(delta: float) -> void:
    ...
    $Renderer.queue_redraw()
    _update_fire_button_ui()
```

Also call `_update_fire_button_ui()` at the end of `_reset_game()` — but only after `_ready` has run (guard with `is_node_ready()`):

```gdscript
if is_node_ready():
    _update_fire_button_ui()
```

- [ ] **Step 4: Tick player cooldown during planning phase too**

The player can fire during planning. The cooldown must tick during both phases, not just simulation. Add to `_process()` before `_step_simulation`:

```gdscript
func _process(delta: float) -> void:
    # Tick player cooldown regardless of phase
    if player_fire_cooldown > 0.0:
        player_fire_cooldown = maxf(0.0, player_fire_cooldown - delta)

    if phase == GamePhase.SIMULATING:
        _step_simulation(delta)
    ...
```

(Keep the per-simulation cooldown tick for enemies in `_step_simulation` — enemies only fire during simulation.)

- [ ] **Step 5: Run the game**

Press F5. Verify:
- Button shows "FIRE" at start
- Clicking fires a missile in the player's current facing direction in both planning and simulation phase
- After firing, button shows "RELOADING..." and the fill sweeps left-to-right over 4 seconds
- Ammo dots decrease each shot; when empty button shows "NO AMMO"
- Cooldown carries over from planning phase into simulation

- [ ] **Step 6: Commit**

```bash
git add game.gd
git commit -m "feat: player real-time firing with cooldown and ammo system"
```

---

## Task 6: Implement enemy real-time firing

**Files:**
- Modify: `game.gd` (add `_step_enemy_firing`, call it from `_step_simulation`)

- [ ] **Step 1: Remove the old enemy fire-at-sim-start block**

In `_start_simulation()`, delete the block that fires one enemy missile per enemy at sim start:

```gdscript
# DELETE this entire block:
if player_alive:
    for enemy in enemies:
        if enemy.alive:
            var to_player: Vector2 = (player_pos - enemy.pos)
            if to_player != Vector2.ZERO:
                var edir: Vector2 = to_player.normalized()
                var e_spawn: Vector2 = enemy.pos + edir * (ENEMY_RADIUS + MISSILE_RADIUS + 2.0)
                missiles.append({
                    "pos": e_spawn,
                    "vel": edir * MISSILE_SPEED,
                    "from_player": false,
                })
```

- [ ] **Step 2: Add `_step_enemy_firing(delta)`**

Add this function to `game.gd`:

```gdscript
func _step_enemy_firing(_delta: float) -> void:
    if not player_alive:
        return

    for enemy in enemies:
        if not enemy.alive:
            continue
        if enemy.fire_cooldown > 0.0:
            continue
        if enemy.missiles_remaining <= 0:
            continue

        var to_player := player_pos - enemy.pos
        if to_player == Vector2.ZERO:
            continue

        # Only fire when roughly facing the player (within 45 degrees)
        var angle_to_player := enemy.vel.normalized().angle_to(to_player.normalized())
        if abs(angle_to_player) > ENEMY_FIRE_ANGLE_THRESHOLD:
            continue

        var edir := to_player.normalized()
        var e_spawn := enemy.pos + edir * (ENEMY_RADIUS + MISSILE_RADIUS + 2.0)
        missiles.append({
            "pos": e_spawn,
            "vel": edir * MISSILE_SPEED,
            "from_player": false,
        })
        enemy.missiles_remaining -= 1
        enemy.fire_cooldown = ENEMY_FIRE_COOLDOWN
```

- [ ] **Step 3: Call it from `_step_simulation`**

In `_step_simulation()`, after the cooldown-ticking block added in Task 3, add:

```gdscript
_step_enemy_firing(delta)
```

- [ ] **Step 4: Run the game**

Press F5. Verify:
- Enemies no longer fire a salvo immediately at sim start
- During simulation, enemies fire when they're roughly aimed at the player
- Enemies stop firing after 6 shots
- Enemy missiles use the orange colour (they use `from_player: false`, same as before)

- [ ] **Step 5: Mark beads issues done**

```bash
bd update vibe-space-pqn --status done
bd update vibe-space-a8l --status done
```

- [ ] **Step 6: Final commit**

```bash
git add game.gd
git commit -m "feat: enemy real-time firing with cooldown and angle-based AI"
```

---

## Done

Both beads issues (vibe-space-pqn, vibe-space-a8l) closed. The game now has:
- Real-time firing in both planning and simulation phases for the player
- 10-missile fixed ammo pool with 4s cooldown, pill button with live fill + missile-glyph dots
- Enemy autonomous firing during simulation with 6 missiles, 3.5s cooldown, 45° angle check
- Clean logic/renderer split: `game.gd` + `game_renderer.gd` + `ammo_display.gd`
