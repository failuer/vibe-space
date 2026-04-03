# Scrap, Newtonian Physics, Tractor Beam & New Weapons — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retrofit the sim loop with Newtonian force-based physics (mass, thrust, gravity), add a collectible scrap resource with tractor beam mechanics, and add homing missile and mine weapons.

**Architecture:** A new `physics_sim.gd` provides static gravity math. `game.gd` gains force accumulators on all bodies and a new thrust-vector planning model. The AI interface is unchanged — AI files still return a desired velocity; `game.gd` converts that to thrust internally. New entity arrays (`scrap`, `mines`) sit alongside the existing `missiles` array.

**Tech Stack:** Godot 4 / GDScript. No external libraries. No automated test framework — verification is done by running the project in the Godot editor and observing behaviour.

**Spec:** `docs/superpowers/specs/2026-04-03-scrap-physics-weapons-design.md`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `physics_sim.gd` | **Create** | Static gravity force calculation utility |
| `game.gd` | **Modify** | All game logic — physics constants, force accumulators, thrust planning, scrap/tractor/weapon arrays, sim loop |
| `game_renderer.gd` | **Modify** | Thrust arrow + path preview, scrap, tractor beam line, homing/mine shapes, HUD layout |
| `ammo_display.gd` | **Remove** | Superseded by new per-weapon slot buttons |
| `README.md` | **Modify** | Update to reflect current game mechanics |

**AI files (`aggressor_ai.gd`, `orbiter_ai.gd`, `flanker_ai.gd`):** No changes needed. They still return a desired velocity from `steer()`. The caller converts it to thrust.

---

## Task 0: Update Documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite README to reflect the actual game**

Replace the contents of `README.md` with:

```markdown
# vibe-space

A turn-based top-down space shooter built in Godot 4.5 (GDScript).

## Gameplay

The game alternates between two phases:

- **Planning** — drag the mouse from your ship to set a thrust vector. A dotted path preview shows where your current momentum + planned thrust will carry you.
- **Simulation** — the world plays out for a fixed 2-second slice, then pauses again.

Destroy all enemy ships to win.

## Physics

All bodies have mass and move under Newtonian physics. Velocity is never set directly — it results from forces:

- **Thrust** — player and enemies apply engine thrust each tick (clamped to engine max)
- **Gravity** — massive bodies (ships, accumulated cargo) attract each other: F = G·m₁·m₂/r²
- **Explosions** — blast impulses are mass-weighted (lighter objects get thrown further)
- **Tractor beam** — spring force during reel-in; rigid pendulum constraint when over cargo capacity
- **Collisions** — momentum-conserving impulse exchange

## Weapons

| Slot | Weapon | Colour | Notes |
|------|--------|--------|-------|
| [1] | Missile | Red | Fires forward, dumb |
| [2] | Homing | Lime | Light homing toward nearest enemy |
| [3] | Mine | Amber | Dropped with player velocity; 1 s arming, 0.2 s trigger delay |

## Scrap & Tractor Beam

Scrap floats in space and is ejected from destroyed enemy ships. Toggle the **TRACTOR** beam to pull nearby scrap aboard. Absorbed scrap adds to your ship's mass (max 4 t cargo). Scrap that exceeds capacity stays tethered as a pendulum — awkward to fly with, but counts toward end-of-round score.

## Controls

| Input | Action |
|-------|--------|
| Mouse | Aim thrust vector |
| Left click | Confirm and start simulation |
| Space / Fire button | Fire selected weapon |
| 1 / 2 / 3 | Select weapon slot |
| T / Tractor button | Toggle tractor beam |

## Project Structure

| File | Role |
|------|------|
| `game.gd` | All game logic — state, phases, input, simulation, AI dispatch |
| `game_renderer.gd` | All rendering — reads game state, never writes it |
| `physics_sim.gd` | Newtonian force utilities (gravity) |
| `game_world.tscn` | Main scene |

## Development Workflow

Tasks and issues are tracked with [beads](https://github.com/yegge/beads) (`bd`). The `docs/superpowers/` directory holds design specs and implementation plans.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README to reflect Newtonian physics and new features"
```

---

## Task 1: Create `physics_sim.gd`

**Files:**
- Create: `physics_sim.gd`

This file contains only the gravity calculation. Everything else (integration loop, force application) lives in `game.gd` where the actual body arrays live.

- [ ] **Step 1: Create the file**

```gdscript
# physics_sim.gd
# Static utility for Newtonian force calculations.
# Owns gravity math only. Integration is done in game.gd.
extends Object
class_name PhysicsSim

# Gameplay-scaled gravitational constant.
# Two 10 t ships 300 px apart feel ~4 units/s² pull — subtle but present.
# Tune freely; higher = more dramatic gravity wells.
const G_SCALED := 40000.0

# Returns the gravitational force vector that body_a exerts ON body_b
# (i.e., directed from b toward a, attracting b toward a).
# Call twice with args swapped to get the equal-and-opposite force on a.
static func gravity_force(pos_a: Vector2, mass_a: float,
                           pos_b: Vector2, mass_b: float) -> Vector2:
    var diff: Vector2 = pos_a - pos_b          # points from b toward a
    var dist_sq: float = diff.length_squared()
    if dist_sq < 100.0:                        # avoid singularity at very close range
        return Vector2.ZERO
    var magnitude: float = G_SCALED * mass_a * mass_b / dist_sq
    return diff.normalized() * magnitude
```

- [ ] **Step 2: Run the project in the Godot editor**

Expected: project opens and plays as before (no changes to gameplay yet — this file is not referenced anywhere yet).

- [ ] **Step 3: Commit**

```bash
git add physics_sim.gd physics_sim.gd.uid
git commit -m "feat: add PhysicsSim utility with gravity_force() helper"
```

---

## Task 2: Add Force Accumulators + Newtonian Integration to `game.gd`

**Files:**
- Modify: `game.gd`

This is the core physics refactor. We replace direct velocity assignment in `_integrate_motion` with force accumulation + `vel += (force/mass) * delta`. Player thrust replaces the arc-planning velocity model. Enemy AI output is still a desired velocity — we convert it to thrust internally so AI files need no changes.

- [ ] **Step 1: Replace physics/speed constants in `game.gd`**

Remove these constants entirely:
```gdscript
const PLAYER_SPEED_DEFAULT := 140.0
const PLAYER_SPEED_MIN := 80.0
const PLAYER_SPEED_MAX := 220.0
const PLAYER_SPEED_DELTA := 80.0
const PLAYER_SPEED_STEP := 25.0
const MAX_TURN_RADIANS := PI / 2.0
const PLAYER_TURN_RATE := MAX_TURN_RADIANS * 1.5 / SIM_DURATION
const ARROW_MIN_DIST := PLAYER_SPEED_MIN * SIM_DURATION
const ARROW_MAX_DIST := PLAYER_SPEED_MAX * SIM_DURATION
const ARROW_NEAR_HALF_WIDTH := 40.0
const ARROW_FAR_HALF_WIDTH := 220.0
```

Add these in their place:
```gdscript
# ── Physics ─────────────────────────────────────────────────────────────────
const PLAYER_MASS             := 10.0   # tonnes
const ENEMY_MASS              := 8.0    # tonnes
const MAX_PLAYER_THRUST       := 1200.0 # force units — gives ~120 units/s² at base mass
const MAX_ENEMY_THRUST        := 1000.0
const GRAVITY_EMIT_MIN_MASS   := 6.0    # bodies below this mass don't emit gravity

# ── Planning UI ──────────────────────────────────────────────────────────────
# Mouse distance (world units) that maps to MAX_PLAYER_THRUST.
const THRUST_ARROW_MAX_LEN    := 180.0
```

Also update `PLAYER_COLOR` from cyan to white:
```gdscript
const PLAYER_COLOR := Color(1.0, 1.0, 1.0)          # white
```

And add new weapon colors after existing color constants:
```gdscript
const MISSILE_COLOR       := Color(1.0, 0.267, 0.267)  # red   #ff4444
const HOMING_COLOR        := Color(0.412, 1.0,  0.490)  # lime  #69ff7d
const MINE_COLOR          := Color(1.0, 0.667, 0.200)   # amber #ffaa33
const SCRAP_COLOR         := Color(0.627, 0.659, 0.690)  # grey  #a0a8b0
```

Remove the old `MISSILE_COLOR := Color(1.0, 1.0, 0.4)` line. **Keep `ENEMY_MISSILE_COLOR` unchanged** (enemy missiles stay orange). The four new color constants above are additions, not replacements for `ENEMY_MISSILE_COLOR`.

- [ ] **Step 2: Replace player state variables**

Remove:
```gdscript
var player_vel: Vector2 = Vector2.UP * PLAYER_SPEED_DEFAULT
var player_speed: float = PLAYER_SPEED_DEFAULT
var planned_player_vel: Vector2 = Vector2.UP * PLAYER_SPEED_DEFAULT
var planned_player_speed: float = PLAYER_SPEED_DEFAULT
var planned_player_target_dir: Vector2 = Vector2.UP
var planned_turn_angle: float = 0.0
var current_turn_rate: float = 0.0
var turn_limit_this_turn: float = MAX_TURN_RADIANS
var turn_speed_min: float = PLAYER_SPEED_MIN
var turn_speed_max: float = PLAYER_SPEED_MAX
```

Add:
```gdscript
var player_vel: Vector2 = Vector2.UP * 80.0    # initial drift velocity
var player_mass: float = PLAYER_MASS
var player_force_acc: Vector2 = Vector2.ZERO
var planned_thrust: Vector2 = Vector2.ZERO     # set each planning phase
```

- [ ] **Step 3: Add `mass` and `force_acc` to each enemy spawn dict in `_reset_game()`**

Find the block inside `_reset_game()` that calls `enemies.append({...})` and add two new keys to each dict:

```gdscript
enemies.append({
    "pos":                enemy_spawns[i].pos,
    "vel":                enemy_spawns[i].vel,
    "alive":              true,
    "missiles_remaining": ENEMY_MAX_MISSILES,
    "fire_cooldown":      0.0,
    "hp":                 ENEMY_MAX_HP,
    "archetype":          archetype,
    "ai_state":           _make_ai_state(archetype),
    "mass":               ENEMY_MASS,       # ← new
    "force_acc":          Vector2.ZERO,     # ← new
})
```

- [ ] **Step 4: Reset new player vars in `_reset_game()`**

Find the "Initial player setup" block and replace the removed variable initialisations:

```gdscript
# replace removed lines with:
player_vel       = Vector2.UP * 80.0
player_mass      = PLAYER_MASS
player_force_acc = Vector2.ZERO
planned_thrust   = Vector2.ZERO
```

Also remove the lines that referenced `player_speed`, `planned_player_vel`, `planned_player_speed`, `planned_player_target_dir`, `planned_turn_angle`, `current_turn_rate`, `turn_limit_this_turn`, `turn_speed_min`, `turn_speed_max`.

- [ ] **Step 5: Update `_start_simulation()`**

Replace the entire function:

```gdscript
func _start_simulation() -> void:
    phase = GamePhase.SIMULATING
    sim_time_left = SIM_DURATION
    sim_real_elapsed = 0.0
    # planned_thrust was set by _update_planned_vector during planning phase — nothing to commit
```

- [ ] **Step 6: Replace `_integrate_motion()` with force-based integration**

Replace the entire function:

```gdscript
func _integrate_motion(delta: float) -> void:
    # ── Gravity accumulation ──────────────────────────────────────────────────
    # Build list of gravity-emitting bodies for pairwise calculation.
    # Only bodies above GRAVITY_EMIT_MIN_MASS emit; all bodies receive.
    var emitters: Array = []
    if player_alive and player_mass >= GRAVITY_EMIT_MIN_MASS:
        emitters.append({
            "pos_ref":  "player",
            "pos":      player_pos,
            "mass":     player_mass,
        })
    for enemy in enemies:
        if enemy.alive and float(enemy.mass) >= GRAVITY_EMIT_MIN_MASS:
            emitters.append({
                "pos_ref": "enemy",
                "enemy":   enemy,
                "pos":     enemy.pos as Vector2,
                "mass":    float(enemy.mass),
            })

    # Apply gravity: each emitter attracts all other bodies
    for emitter in emitters:
        var ep: Vector2 = emitter.pos as Vector2
        var em: float   = emitter.mass as float

        # → player
        if player_alive and emitter.get("pos_ref") != "player":
            player_force_acc += PhysicsSim.gravity_force(ep, em, player_pos, player_mass)

        # → enemies
        for enemy in enemies:
            if not enemy.alive:
                continue
            if emitter.get("pos_ref") == "enemy" and emitter.get("enemy") == enemy:
                continue  # skip self
            var gf: Vector2 = PhysicsSim.gravity_force(ep, em, enemy.pos as Vector2, float(enemy.mass))
            enemy.force_acc = (enemy.force_acc as Vector2) + gf

    # ── Player integration ────────────────────────────────────────────────────
    if player_alive:
        player_force_acc += planned_thrust
        var accel: Vector2 = player_force_acc / player_mass
        player_vel    += accel * delta
        player_pos    += player_vel * delta
        player_force_acc = Vector2.ZERO

    # ── Enemy integration ─────────────────────────────────────────────────────
    for enemy in enemies:
        if not enemy.alive:
            continue
        var accel: Vector2 = (enemy.force_acc as Vector2) / float(enemy.mass)
        enemy.vel       = (enemy.vel as Vector2) + accel * delta
        enemy.pos       = (enemy.pos as Vector2) + (enemy.vel as Vector2) * delta
        enemy.force_acc = Vector2.ZERO

    # ── Missiles (no mass — just kinematic) ───────────────────────────────────
    for missile in missiles:
        missile.pos = (missile.pos as Vector2) + (missile.vel as Vector2) * delta
```

- [ ] **Step 7: Update the AI dispatcher in `_step_simulation()` to convert desired velocity to thrust**

Find the section in `_step_simulation` that calls `enemy.vel = ai.steer(...)` and replace it:

```gdscript
# Steering — AI returns desired velocity; we convert to thrust
var desired_vel: Vector2 = ai.steer(enemy, self, game_delta)
var vel_error: Vector2   = desired_vel - (enemy.vel as Vector2)
var raw_thrust: Vector2  = vel_error * float(enemy.mass) / maxf(game_delta, 0.001)
var thrust: Vector2      = raw_thrust.clamped(MAX_ENEMY_THRUST)
enemy.force_acc = (enemy.force_acc as Vector2) + thrust
```

- [ ] **Step 8: Replace `_update_planned_vector()` with thrust-vector version**

Replace the entire function:

```gdscript
func _update_planned_vector(mouse_world: Vector2) -> void:
    if not player_alive:
        return
    var offset: Vector2 = mouse_world - player_pos
    var raw_len: float  = offset.length()
    if raw_len < 1.0:
        planned_thrust = Vector2.ZERO
        return
    var ratio: float   = minf(raw_len, THRUST_ARROW_MAX_LEN) / THRUST_ARROW_MAX_LEN
    planned_thrust     = offset.normalized() * ratio * MAX_PLAYER_THRUST
```

- [ ] **Step 9: Remove `_arc_endpoint()` and `_compute_turn_limit_for_speed()`**

Delete both functions entirely — they are no longer used.

- [ ] **Step 10: Remove stale references in `_step_simulation()`**

In the block at the end of `_step_simulation()` that runs when `sim_time_left <= 0.0`:

Remove these lines (they reference removed variables):
```gdscript
planned_player_vel = player_vel
planned_player_speed = player_speed
turn_limit_this_turn = _compute_turn_limit_for_speed(player_speed)
turn_speed_min = maxf(PLAYER_SPEED_MIN, player_speed - PLAYER_SPEED_DELTA)
turn_speed_max = player_speed + PLAYER_SPEED_DELTA
```

Replace with nothing (no momentum re-initialisation needed — `player_vel` naturally carries over).

- [ ] **Step 11: Run the project**

Expected:
- Game launches and enemies move (they'll be force-driven now, but AI output is still a desired velocity so behaviour should look similar)
- Player drifts in a straight line (thrust is zero until mouse interaction is updated)
- No script errors in the Godot output panel

- [ ] **Step 12: Commit**

```bash
git add game.gd physics_sim.gd
git commit -m "feat: retrofit game loop with Newtonian force-based physics (mass, thrust, gravity)"
```

---

## Task 3: Replace Planning UI — Thrust Arrow + Dotted Path Preview

**Files:**
- Modify: `game_renderer.gd`
- Modify: `game.gd` (minor — expose `planned_thrust` for renderer)

Remove the wedge/arc drawing code and replace with a thrust arrow and dotted predicted path.

- [ ] **Step 1: Remove old planning draw functions from `game_renderer.gd`**

Delete these three functions entirely:
- `_draw_turn_wedge()`
- `_draw_planned_path()`
- `_draw_planned_ghost()`

- [ ] **Step 2: Add new planning draw functions to `game_renderer.gd`**

Add after `_draw_hp_bar()`:

```gdscript
func _draw_thrust_arrow() -> void:
    var thrust: Vector2 = game.planned_thrust
    if thrust == Vector2.ZERO:
        return
    var raw_len: float = thrust.length()
    if raw_len < 1.0:
        return
    var ratio: float    = minf(raw_len / game.MAX_PLAYER_THRUST, 1.0)
    var dir: Vector2    = thrust.normalized()
    var arrow_len: float = ratio * game.THRUST_ARROW_MAX_LEN

    var tip: Vector2    = game.player_pos + dir * arrow_len
    var shaft_col       := Color(0.3, 1.0, 0.45, 0.7)
    var head_size: float = 8.0

    # Shaft
    draw_line(game.player_pos, tip, shaft_col, 2.0)

    # Arrowhead
    var perp: Vector2 = Vector2(-dir.y, dir.x)
    draw_line(tip, tip - dir * head_size + perp * head_size * 0.5, shaft_col, 2.0)
    draw_line(tip, tip - dir * head_size - perp * head_size * 0.5, shaft_col, 2.0)

    # Dim the arrow when thrust is clamped (mouse beyond max range)
    if ratio >= 1.0:
        draw_circle(tip, 3.0, Color(0.3, 1.0, 0.45, 0.4))


func _draw_thrust_preview() -> void:
    var thrust: Vector2  = game.planned_thrust
    var steps: int       = 20
    var dt: float        = game.SIM_DURATION / float(steps)
    var mass: float      = game.player_mass

    var ppos: Vector2 = game.player_pos
    var pvel: Vector2 = game.player_vel
    var accel: Vector2 = thrust / mass

    var dot_col := Color(0.3, 1.0, 0.45, 0.35)
    for i in steps:
        pvel += accel * dt
        ppos += pvel * dt
        draw_circle(ppos, 2.5, dot_col)

    # Ghost ship at endpoint, facing predicted velocity
    if pvel.length() > 0.1:
        var ghost_col := game.PLAYER_COLOR
        ghost_col.a   = 0.3
        _draw_ship_triangle(ppos, pvel, game.PLAYER_RADIUS, ghost_col)
```

- [ ] **Step 3: Update `_draw()` in `game_renderer.gd` to call new functions**

Find the planning phase draw block:
```gdscript
if game.phase == Game.GamePhase.PLANNING and game.player_alive:
    _draw_turn_wedge()
    _draw_planned_path()
    _draw_planned_ghost()
```

Replace with:
```gdscript
if game.phase == Game.GamePhase.PLANNING and game.player_alive:
    _draw_thrust_arrow()
    _draw_thrust_preview()
```

- [ ] **Step 4: Update player ship color in `_draw()` to use white**

The player triangle is already drawn with `game.PLAYER_COLOR` which is now white — no change needed in the draw call. Verify the constant was updated in Task 2.

- [ ] **Step 5: Run the project**

Expected:
- During planning phase: a green thrust arrow appears from ship toward mouse
- Dotted path shows where momentum + thrust will carry the ship
- Ghost ship appears at the path endpoint
- No wedge or arc visible

- [ ] **Step 6: Commit**

```bash
git add game.gd game_renderer.gd
git commit -m "feat: replace planning arc/wedge with thrust vector arrow and dotted path preview"
```

---

## Task 4: Scrap System

**Files:**
- Modify: `game.gd`
- Modify: `game_renderer.gd`

Add scrap as persistent physics bodies. Scrap spawns at game start and from enemy ship explosions.

- [ ] **Step 1: Add scrap constants to `game.gd`**

```gdscript
# ── Scrap ────────────────────────────────────────────────────────────────────
const SCRAP_RADIUS         := 10.0
const SCRAP_MASS_MIN       := 1.0   # tonnes
const SCRAP_MASS_MAX       := 3.0
const SCRAP_SPAWN_COUNT    := 3     # pieces placed at game start
const SCRAP_FROM_EXPLOSION := 2     # pieces per destroyed enemy ship
```

- [ ] **Step 2: Add scrap array variable in `game.gd`**

After the `debris: Array` declaration:
```gdscript
var scrap: Array = []  # each: {pos, vel, mass, force_acc, angle, angular_vel}
```

- [ ] **Step 3: Add `_spawn_scrap_piece()` helper in `game.gd`**

```gdscript
func _spawn_scrap_piece(pos: Vector2, vel: Vector2) -> void:
    scrap.append({
        "pos":         pos,
        "vel":         vel,
        "mass":        randf_range(SCRAP_MASS_MIN, SCRAP_MASS_MAX),
        "force_acc":   Vector2.ZERO,
        "angle":       randf() * TAU,
        "angular_vel": randf_range(-1.5, 1.5),
    })
```

- [ ] **Step 4: Spawn starting scrap in `_reset_game()`**

After `debris.clear()`, add:
```gdscript
scrap.clear()
for _i in SCRAP_SPAWN_COUNT:
    var angle: float  = randf() * TAU
    var dist: float   = randf_range(200.0, 500.0)
    var spawn_pos     := Vector2(cos(angle), sin(angle)) * dist
    var drift_vel     := Vector2(randf_range(-30.0, 30.0), randf_range(-30.0, 30.0))
    _spawn_scrap_piece(spawn_pos, drift_vel)
```

- [ ] **Step 5: Spawn scrap from enemy explosions in `_spawn_explosion()`**

Find the `_spawn_explosion()` function. After the existing debris spawn loop, add:

```gdscript
if is_ship:
    for _i in SCRAP_FROM_EXPLOSION:
        var angle: float = randf() * TAU
        var speed: float = randf_range(40.0, 120.0)
        var scatter_vel  := vel + Vector2(cos(angle), sin(angle)) * speed
        _spawn_scrap_piece(pos + Vector2(cos(angle), sin(angle)) * 20.0, scatter_vel)
```

- [ ] **Step 6: Integrate scrap physics in `_integrate_motion()`**

In the gravity accumulation block, add scrap as receivers (scrap does not emit gravity):
```gdscript
# After the enemy gravity application loop, inside the emitters loop:
for piece in scrap:
    var gf: Vector2 = PhysicsSim.gravity_force(ep, em, piece.pos as Vector2, float(piece.mass))
    piece.force_acc = (piece.force_acc as Vector2) + gf
```

After the missiles kinematic block at the end of `_integrate_motion()`, add:
```gdscript
# ── Scrap integration ─────────────────────────────────────────────────────────
for piece in scrap:
    var accel: Vector2 = (piece.force_acc as Vector2) / float(piece.mass)
    piece.vel      = (piece.vel as Vector2) + accel * delta
    piece.pos      = (piece.pos as Vector2) + (piece.vel as Vector2) * delta
    piece.angle    = float(piece.angle) + float(piece.angular_vel) * delta
    piece.force_acc = Vector2.ZERO
```

- [ ] **Step 7: Cull out-of-bounds scrap in `_cull_offscreen_objects()`**

Add at the end of the function:
```gdscript
var live_scrap: Array = []
for piece in scrap:
    if (piece.pos as Vector2).length() <= SCENE_RADIUS:
        live_scrap.append(piece)
scrap = live_scrap
```

- [ ] **Step 8: Draw scrap in `game_renderer.gd`**

Add a new draw function:

```gdscript
func _draw_scrap() -> void:
    for piece in game.scrap:
        var pos: Vector2   = piece.pos as Vector2
        var angle: float   = piece.angle as float
        var mass: float    = float(piece.mass)
        # Size scales with mass: 1t → r=7, 3t → r=11
        var r: float       = 6.0 + mass * 1.7
        var col: Color     = game.SCRAP_COLOR

        # Irregular hexagon — 6 verts with slight radius variation
        var verts := PackedVector2Array()
        var offsets := [0.9, 1.1, 0.8, 1.0, 1.15, 0.85]
        for i in 6:
            var a: float = angle + float(i) * TAU / 6.0
            verts.append(pos + Vector2(cos(a), sin(a)) * r * float(offsets[i]))
        var cols := PackedColorArray()
        cols.resize(6)
        cols.fill(col)
        draw_polygon(verts, cols)

        # Outline
        for i in 6:
            draw_line(verts[i], verts[(i + 1) % 6], Color(col.r, col.g, col.b, 0.5), 1.0)
```

- [ ] **Step 9: Call `_draw_scrap()` from `_draw()` in `game_renderer.gd`**

Add after `_draw_debris()`:
```gdscript
_draw_scrap()
```

- [ ] **Step 10: Run the project**

Expected:
- 3 grey hexagonal scrap pieces visible in space at game start, drifting slowly
- Destroying an enemy spawns 2 scrap pieces scattering from the explosion
- Scrap is affected by gravity (subtle pull toward ships over time)

- [ ] **Step 11: Commit**

```bash
git add game.gd game_renderer.gd
git commit -m "feat: add scrap resource — spawns at start and from enemy explosions, full physics integration"
```

---

## Task 5: Tractor Beam

**Files:**
- Modify: `game.gd`
- Modify: `game_renderer.gd`

Toggle beam pulls nearest scrap via spring force. Absorbed scrap adds to player mass. Over-capacity scrap dangles as a rigid pendulum.

- [ ] **Step 1: Add tractor beam constants to `game.gd`**

```gdscript
# ── Tractor beam ─────────────────────────────────────────────────────────────
const TRACTOR_RANGE       := 250.0   # search radius (units)
const TRACTOR_SPRING_K    := 0.2     # spring constant for reel-in force
const TRACTOR_DOCKING_DIST:= 30.0   # distance at which scrap is absorbed
const TETHER_LENGTH       := 200.0   # max tether length when over-capacity
const PLAYER_CARGO_CAP    := 4.0     # max tonnes that can be absorbed
```

- [ ] **Step 2: Add tractor beam state variables to `game.gd`**

```gdscript
# ── Tractor beam state ────────────────────────────────────────────────────────
var tractor_active: bool    = false
var tractor_target: int     = -1    # index into scrap[], -1 = no target
var player_cargo_aboard: float = 0.0
```

- [ ] **Step 3: Reset tractor state in `_reset_game()`**

```gdscript
tractor_active      = false
tractor_target      = -1
player_cargo_aboard = 0.0
```

- [ ] **Step 4: Add `_step_tractor_beam()` to `game.gd`**

```gdscript
func _step_tractor_beam(delta: float) -> void:
    if not tractor_active or not player_alive:
        return

    # Re-validate target index (scrap array may have changed)
    if tractor_target >= scrap.size():
        tractor_target = -1

    # Search for nearest target if none
    if tractor_target == -1:
        var nearest_dist: float = TRACTOR_RANGE
        var nearest_idx:  int   = -1
        for i in scrap.size():
            var d: float = player_pos.distance_to(scrap[i].pos as Vector2)
            if d < nearest_dist:
                nearest_dist = d
                nearest_idx  = i
        tractor_target = nearest_idx
        return  # start pulling next tick

    var piece: Dictionary = scrap[tractor_target]
    var diff: Vector2     = player_pos - (piece.pos as Vector2)
    var dist: float       = diff.length()
    if dist < 1.0:
        return

    var remaining_cap: float = PLAYER_CARGO_CAP - player_cargo_aboard
    var fits: bool           = float(piece.mass) <= remaining_cap + 0.01

    if fits:
        # ── Spring reel-in ───────────────────────────────────────────────────
        var spring_force: Vector2 = diff.normalized() * TRACTOR_SPRING_K * dist
        piece.force_acc = (piece.force_acc as Vector2) + spring_force
        # Reaction force on player (equal and opposite, mass-weighted feel)
        player_force_acc += -spring_force * (float(piece.mass) / player_mass)

        # Absorb when close enough
        if dist <= TRACTOR_DOCKING_DIST:
            player_cargo_aboard += float(piece.mass)
            player_mass         += float(piece.mass)
            scrap.remove_at(tractor_target)
            tractor_target = -1

    else:
        # ── Over-capacity: rigid tether (pendulum constraint) ─────────────────
        if dist > TETHER_LENGTH:
            var penetration: float = dist - TETHER_LENGTH
            var axis: Vector2      = diff.normalized()
            var total_mass: float  = player_mass + float(piece.mass)
            # Position correction split by mass ratio
            player_pos            += axis * penetration * (float(piece.mass) / total_mass)
            piece.pos              = (piece.pos as Vector2) + (-axis) * penetration * (player_mass / total_mass)
            # Remove outward velocity component from both bodies
            var player_outward: float = player_vel.dot(-axis)
            var piece_outward: float  = (piece.vel as Vector2).dot(axis)
            if player_outward < 0.0:
                player_vel -= -axis * player_outward
            if piece_outward < 0.0:
                piece.vel = (piece.vel as Vector2) - axis * piece_outward
```

- [ ] **Step 5: Call `_step_tractor_beam()` in `_step_simulation()`**

Add after the gravity step (before `_integrate_motion`):
```gdscript
_step_tractor_beam(game_delta)
```

- [ ] **Step 6: Wire up tractor beam toggle in `_unhandled_input()`**

Add key handler inside the `phase != GamePhase.PLANNING` guard (after the mouse handlers):
```gdscript
if event is InputEventKey and event.pressed and not event.echo:
    if event.keycode == KEY_T:
        tractor_active = not tractor_active
        if not tractor_active:
            tractor_target = -1
```

- [ ] **Step 7: Draw the tractor beam in `game_renderer.gd`**

Add a new draw function:

```gdscript
func _draw_tractor_beam() -> void:
    if not game.tractor_active or not game.player_alive:
        return

    var gold   := Color(0.961, 0.773, 0.259)  # #f5c542
    var red    := Color(1.0, 0.267, 0.267, 0.8)

    if game.tractor_target == -1:
        # Searching — draw a short sweeping stub
        draw_circle(game.player_pos, 6.0, Color(gold.r, gold.g, gold.b, 0.4))
        return

    if game.tractor_target >= game.scrap.size():
        return

    var piece: Dictionary = game.scrap[game.tractor_target]
    var ppos:  Vector2    = piece.pos as Vector2
    var remaining_cap: float = game.PLAYER_CARGO_CAP - game.player_cargo_aboard
    var fits: bool           = float(piece.mass) <= remaining_cap + 0.01
    var beam_col: Color      = gold if fits else red

    draw_line(game.player_pos, ppos, beam_col, 1.5)
    draw_circle(ppos, game.SCRAP_RADIUS * 1.3, Color(beam_col.r, beam_col.g, beam_col.b, 0.25))
```

- [ ] **Step 8: Call `_draw_tractor_beam()` in `_draw()` in `game_renderer.gd`**

Add after `_draw_scrap()`:
```gdscript
_draw_tractor_beam()
```

- [ ] **Step 9: Run the project**

Expected:
- Press T during planning or mid-game to toggle the tractor beam
- When ON and near scrap: a gold beam line connects ship to scrap; scrap slowly pulls toward you; you feel a slight tug
- When scrap arrives and fits: it disappears (absorbed), player visually gets heavier (wider turns, slower acceleration)
- When scrap is too heavy: beam turns red; scrap dangles at tether length and swings when you change direction

- [ ] **Step 10: Commit**

```bash
git add game.gd game_renderer.gd
git commit -m "feat: tractor beam — spring reel-in, cargo absorption, over-capacity pendulum tether"
```

---

## Task 6: Homing Missile

**Files:**
- Modify: `game.gd`
- Modify: `game_renderer.gd`

Slot 2 weapon. Fires forward, then steers gently toward the nearest enemy each tick.

- [ ] **Step 1: Add homing missile constants to `game.gd`**

```gdscript
# ── Homing missile ───────────────────────────────────────────────────────────
const PLAYER_MAX_HOMING     := 5
const PLAYER_HOMING_COOLDOWN:= 4.5
const HOMING_TURN_RATE      := 1.2   # radians/sec steering correction
```

- [ ] **Step 2: Add homing missile state variables to `game.gd`**

```gdscript
var player_homing_remaining: int   = PLAYER_MAX_HOMING
var player_homing_cooldown:  float = 0.0
```

- [ ] **Step 3: Add active weapon selection variable and keyboard shortcuts**

```gdscript
var active_weapon: int = 0   # 0 = missile, 1 = homing, 2 = mine
```

In `_unhandled_input()`, inside the key-press block, add:
```gdscript
if event.keycode == KEY_1:
    active_weapon = 0
elif event.keycode == KEY_2:
    active_weapon = 1
elif event.keycode == KEY_3:
    active_weapon = 2
```

- [ ] **Step 4: Reset in `_reset_game()`**

```gdscript
player_homing_remaining = PLAYER_MAX_HOMING
player_homing_cooldown  = 0.0
active_weapon           = 0
```

- [ ] **Step 5: Tick homing cooldown in `_step_simulation()`**

In the cooldown tick block (where `player_fire_cooldown` is decremented), add:
```gdscript
if player_homing_cooldown > 0.0:
    player_homing_cooldown = maxf(0.0, player_homing_cooldown - game_delta)
```

- [ ] **Step 6: Update `_try_fire_player()` to fire based on `active_weapon`**

Replace the entire function:

```gdscript
func _try_fire_player() -> void:
    if not player_alive:
        return
    match active_weapon:
        0: _fire_missile()
        1: _fire_homing()
        2: _fire_mine()


func _fire_missile() -> void:
    if player_missiles_remaining <= 0 or player_fire_cooldown > 0.0:
        return
    var dir: Vector2     = player_vel.normalized()
    var spawn_pos: Vector2 = player_pos + dir * (PLAYER_RADIUS + MISSILE_RADIUS + 2.0)
    missiles.append({
        "pos":        spawn_pos,
        "vel":        dir * MISSILE_SPEED,
        "from_player": true,
        "power":      MISSILE_POWER,
        "homing":     false,
    })
    player_missiles_remaining -= 1
    player_fire_cooldown       = PLAYER_FIRE_COOLDOWN


func _fire_homing() -> void:
    if player_homing_remaining <= 0 or player_homing_cooldown > 0.0:
        return
    var dir: Vector2       = player_vel.normalized()
    var spawn_pos: Vector2 = player_pos + dir * (PLAYER_RADIUS + MISSILE_RADIUS + 2.0)
    missiles.append({
        "pos":        spawn_pos,
        "vel":        dir * MISSILE_SPEED,
        "from_player": true,
        "power":      MISSILE_POWER,
        "homing":     true,
    })
    player_homing_remaining -= 1
    player_homing_cooldown   = PLAYER_HOMING_COOLDOWN


func _fire_mine() -> void:
    pass  # stub — implemented in Task 7
```

- [ ] **Step 7: Add homing steering step in `_step_simulation()`**

After the AI dispatcher loop (step 2 in `_step_simulation`), add a homing pass:

```gdscript
# Homing missile steering
for missile in missiles:
    if not (missile.get("homing", false) as bool):
        continue
    if not (missile.from_player as bool):
        continue
    var nearest_enemy: Dictionary = {}
    var nearest_dist: float       = INF
    for enemy in enemies:
        if not enemy.alive:
            continue
        var d: float = (missile.pos as Vector2).distance_to(enemy.pos as Vector2)
        if d < nearest_dist:
            nearest_dist  = d
            nearest_enemy = enemy
    if nearest_enemy.is_empty():
        continue
    var to_target: Vector2  = ((nearest_enemy.pos as Vector2) - (missile.pos as Vector2)).normalized()
    var current_dir: Vector2 = (missile.vel as Vector2).normalized()
    var new_dir: Vector2    = current_dir.lerp(to_target, HOMING_TURN_RATE * game_delta).normalized()
    missile.vel             = new_dir * MISSILE_SPEED
```

- [ ] **Step 8: Draw homing missiles distinctly in `game_renderer.gd`**

Update `_draw()` missile loop to branch on `homing`:

```gdscript
for missile in game.missiles:
    var is_homing: bool = missile.get("homing", false) as bool
    if not (missile.from_player as bool):
        _draw_missile_triangle(missile.pos as Vector2, missile.vel as Vector2, game.MISSILE_RADIUS, game.ENEMY_MISSILE_COLOR)
    elif is_homing:
        _draw_homing_missile(missile.pos as Vector2, missile.vel as Vector2)
    else:
        _draw_missile_triangle(missile.pos as Vector2, missile.vel as Vector2, game.MISSILE_RADIUS, game.MISSILE_COLOR)
```

Add new draw function:

```gdscript
func _draw_homing_missile(center: Vector2, vel: Vector2) -> void:
    var fwd: Vector2   = vel.normalized() if vel != Vector2.ZERO else Vector2.UP
    var right: Vector2 = Vector2(-fwd.y, fwd.x)
    var r: float       = game.MISSILE_RADIUS
    var col: Color     = game.HOMING_COLOR

    # Thin needle body
    var tip:  Vector2 = center + fwd  * r * 1.4
    var bl:   Vector2 = center - fwd  * r * 0.9 + right * r * 0.25
    var br:   Vector2 = center - fwd  * r * 0.9 - right * r * 0.25
    draw_polygon(PackedVector2Array([tip, bl, br]), PackedColorArray([col, col, col]))

    # Delta wing outline (larger triangle over rear half)
    var wl: Vector2 = center - fwd * r * 0.1 + right * r * 1.1
    var wr: Vector2 = center - fwd * r * 0.1 - right * r * 1.1
    var wt: Vector2 = center + fwd * r * 0.4
    draw_line(wt, wl, Color(col.r, col.g, col.b, 0.8), 1.2)
    draw_line(wt, wr, Color(col.r, col.g, col.b, 0.8), 1.2)
    draw_line(wl, wr, Color(col.r, col.g, col.b, 0.5), 1.2)
```

- [ ] **Step 9: Run the project**

Expected:
- Press 2 to select homing, then Space/Fire to launch
- Homing missiles (lime, winged shape) gradually steer toward enemies
- Fast enemies can dodge them; slow ones get hit reliably

- [ ] **Step 10: Commit**

```bash
git add game.gd game_renderer.gd
git commit -m "feat: homing missile — slot 2, light per-tick steering toward nearest enemy, lime color"
```

---

## Task 7: Mine

**Files:**
- Modify: `game.gd`
- Modify: `game_renderer.gd`

Slot 3 weapon. Dropped with player's velocity, 1 s arming time, 0.2 s proximity trigger delay.

- [ ] **Step 1: Add mine constants to `game.gd`**

```gdscript
# ── Mine ─────────────────────────────────────────────────────────────────────
const PLAYER_MAX_MINES      := 3
const PLAYER_MINE_COOLDOWN  := 2.0
const MINE_RADIUS           := 9.0
const MINE_ARM_TIME         := 1.0   # seconds before proximity trigger activates
const MINE_TRIGGER_RADIUS   := 40.0  # proximity detection radius
const MINE_TRIGGER_DELAY    := 0.2   # seconds after trigger before detonation
```

- [ ] **Step 2: Add mine state variables and array to `game.gd`**

```gdscript
var player_mine_remaining: int   = PLAYER_MAX_MINES
var player_mine_cooldown:  float = 0.0
var mines: Array = []
# mine dict: {pos, vel, arm_timer, trigger_timer, triggered, alive}
```

- [ ] **Step 3: Reset mines in `_reset_game()`**

```gdscript
player_mine_remaining = PLAYER_MAX_MINES
player_mine_cooldown  = 0.0
mines.clear()
```

- [ ] **Step 4: Add `_fire_mine()` to `game.gd`**

```gdscript
func _fire_mine() -> void:
    if player_mine_remaining <= 0 or player_mine_cooldown > 0.0:
        return
    mines.append({
        "pos":          player_pos,
        "vel":          player_vel,       # inherits player velocity
        "arm_timer":    MINE_ARM_TIME,
        "trigger_timer": 0.0,
        "triggered":    false,
        "alive":        true,
    })
    player_mine_remaining -= 1
    player_mine_cooldown   = PLAYER_MINE_COOLDOWN
```

- [ ] **Step 5: Tick mine cooldown in the cooldown block in `_step_simulation()`**

```gdscript
if player_mine_cooldown > 0.0:
    player_mine_cooldown = maxf(0.0, player_mine_cooldown - game_delta)
```

- [ ] **Step 6: Add `_step_mines()` to `game.gd`**

```gdscript
func _step_mines(delta: float) -> void:
    var live_mines: Array = []
    for mine in mines:
        if not (mine.alive as bool):
            continue

        # Drift
        mine.pos = (mine.pos as Vector2) + (mine.vel as Vector2) * delta

        # Tick arm timer
        if (mine.arm_timer as float) > 0.0:
            mine.arm_timer = maxf(0.0, float(mine.arm_timer) - delta)

        # Tick trigger countdown
        if (mine.triggered as bool):
            mine.trigger_timer = maxf(0.0, float(mine.trigger_timer) - delta)
            if float(mine.trigger_timer) <= 0.0:
                _spawn_explosion(mine.pos as Vector2, mine.vel as Vector2, false)
                _apply_blast_impulse(mine.pos as Vector2, EXPLOSION_BLAST_RADIUS_MISSILE)
                mine.alive = false
                continue

        # Proximity check (only when armed and not yet triggered)
        if float(mine.arm_timer) <= 0.0 and not (mine.triggered as bool):
            var mpos: Vector2 = mine.pos as Vector2
            var triggered := false

            # Check player
            if player_alive and mpos.distance_to(player_pos) < MINE_TRIGGER_RADIUS:
                triggered = true

            # Check enemies
            if not triggered:
                for enemy in enemies:
                    if enemy.alive and mpos.distance_to(enemy.pos as Vector2) < MINE_TRIGGER_RADIUS:
                        triggered = true
                        break

            # Check scrap (massive bodies)
            if not triggered:
                for piece in scrap:
                    if mpos.distance_to(piece.pos as Vector2) < MINE_TRIGGER_RADIUS:
                        triggered = true
                        break

            if triggered:
                mine.triggered    = true
                mine.trigger_timer = MINE_TRIGGER_DELAY

        live_mines.append(mine)
    mines = live_mines
```

- [ ] **Step 7: Handle mine–weapon collisions in `_handle_collisions()`**

Add at the end of `_handle_collisions()`:

```gdscript
# Weapon hits on mines (missiles/explosions destroy mines instantly)
for mine in mines:
    if not (mine.alive as bool):
        continue
    for missile in missiles:
        if _circles_overlap(missile.pos as Vector2, MISSILE_RADIUS, mine.pos as Vector2, MINE_RADIUS):
            _spawn_explosion(mine.pos as Vector2, mine.vel as Vector2, false)
            _apply_blast_impulse(mine.pos as Vector2, EXPLOSION_BLAST_RADIUS_MISSILE)
            mine.alive     = false
            missile.pos.x  = SCENE_RADIUS * 2.0
            break
```

- [ ] **Step 8: Call `_step_mines()` in `_step_simulation()`**

Add inside `if game_delta > 0.0:`, after `_step_explosions(game_delta)`:
```gdscript
_step_mines(game_delta)
```

- [ ] **Step 9: Cull out-of-range mines in `_cull_offscreen_objects()`**

```gdscript
var live_mines_culled: Array = []
for mine in mines:
    if (mine.pos as Vector2).length() <= SCENE_RADIUS:
        live_mines_culled.append(mine)
mines = live_mines_culled
```

- [ ] **Step 10: Clear mines on game reset — already done in Step 3**

Verify `mines.clear()` is in `_reset_game()`.

- [ ] **Step 11: Draw mines in `game_renderer.gd`**

Add new draw function:

```gdscript
func _draw_mines() -> void:
    for mine in game.mines:
        if not (mine.alive as bool):
            continue
        var pos:    Vector2 = mine.pos as Vector2
        var armed:  bool    = float(mine.arm_timer) <= 0.0
        var triggered: bool = mine.triggered as bool
        var r:      float   = game.MINE_RADIUS
        var col:    Color   = game.MINE_COLOR

        # Pulse when triggered
        var alpha: float = 1.0
        if triggered:
            alpha = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)

        # 8 spike lines
        for i in 8:
            var a: float    = float(i) * TAU / 8.0
            var inner: Vector2 = pos + Vector2(cos(a), sin(a)) * r
            var outer: Vector2 = pos + Vector2(cos(a), sin(a)) * (r + 5.0)
            draw_line(inner, outer, Color(col.r, col.g, col.b, alpha * 0.9), 1.5)
            draw_circle(outer, 1.2, Color(col.r, col.g, col.b, alpha))

        # Body circle
        var fill_col := Color(col.r, col.g, col.b, alpha * 0.15)
        draw_circle(pos, r, fill_col)
        draw_arc(pos, r, 0.0, TAU, 24, Color(col.r, col.g, col.b, alpha), 1.5)

        # Dim during arming (draw an additional arming ring that shrinks)
        if not armed:
            var arm_ratio: float = float(mine.arm_timer) / game.MINE_ARM_TIME
            draw_arc(pos, r * (1.0 + arm_ratio * 0.5), 0.0, TAU, 16,
                     Color(col.r, col.g, col.b, 0.3 * arm_ratio), 1.0)
```

- [ ] **Step 12: Call `_draw_mines()` in `_draw()` in `game_renderer.gd`**

Add after `_draw_tractor_beam()`:
```gdscript
_draw_mines()
```

- [ ] **Step 13: Run the project**

Expected:
- Press 3 to select mine, Space to drop — mine appears behind you drifting with your velocity
- During 1 s arming: faint pulsing ring visible, mine won't proximity-trigger
- After 1 s: approaching ships cause a 0.2 s countdown flash before explosion
- Player can trigger their own mine after arming — watch your 6
- Missiles and explosions destroy mines early

- [ ] **Step 14: Commit**

```bash
git add game.gd game_renderer.gd
git commit -m "feat: mine — slot 3, drops with player velocity, 1 s arming, 0.2 s proximity trigger"
```

---

## Task 8: HUD Rebuild

**Files:**
- Modify: `game.gd`
- Modify: `game_renderer.gd`
- Modify: `ammo_display.gd` → effectively superseded (can be left or removed)

Replace the single fire button + ammo display with: HP pips (top-left), tractor toggle (top-center), mass + cargo cluster (top-right), weapon slots 1/2/3 (bottom-center).

The new UI is built programmatically in `_ready()` — no scene file edits needed.

- [ ] **Step 1: Add UI node references to `game.gd`**

Replace the existing `@onready` UI declarations:
```gdscript
@onready var camera:        Camera2D = $Camera2D
@onready var message_label: Label    = $CanvasLayer/MessageLabel
@onready var restart_button: Button  = $CanvasLayer/RestartButton
```

Remove (these nodes will be replaced):
```gdscript
@onready var fire_button:    Button    = $CanvasLayer/FireButtonContainer/FireButton
@onready var cooldown_fill:  ColorRect = $CanvasLayer/FireButtonContainer/FireButton/CooldownFill
@onready var ammo_display:   Control   = $CanvasLayer/FireButtonContainer/AmmoDisplay
```

Add new node references (these are created dynamically in `_ready()`):
```gdscript
var slot_buttons:    Array[Button] = []    # [missile, homing, mine]
var slot_cooldowns:  Array[ColorRect] = [] # cooldown fill per slot
var tractor_button:  Button
var mass_label:      Label
var cargo_label:     Label
var cargo_bar:       ColorRect
var cargo_bar_bg:    ColorRect
```

- [ ] **Step 2: Replace `_ready()` UI setup in `game.gd`**

Delete the existing fire button style setup code and `ammo_display` initialisation. Replace with a call to a new function at the end of `_ready()`:

```gdscript
func _ready() -> void:
    randomize()
    _generate_stars()
    _reset_game()
    restart_button.pressed.connect(_on_restart_pressed)
    _build_hud()
```

- [ ] **Step 3: Add `_build_hud()` to `game.gd`**

```gdscript
func _build_hud() -> void:
    var canvas: CanvasLayer = $CanvasLayer

    # ── Shared style helpers ──────────────────────────────────────────────────
    var weapon_colors: Array[Color] = [
        MISSILE_COLOR,   # slot 0
        HOMING_COLOR,    # slot 1
        MINE_COLOR,      # slot 2
    ]
    var weapon_names: Array[String] = ["MISSILE", "HOMING", "MINE"]

    # ── Bottom-center: weapon slots ───────────────────────────────────────────
    var slot_container := HBoxContainer.new()
    slot_container.add_theme_constant_override("separation", 8)
    slot_container.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    slot_container.anchor_top    = 1.0
    slot_container.anchor_bottom = 1.0
    slot_container.anchor_left   = 0.5
    slot_container.anchor_right  = 0.5
    slot_container.offset_top    = -86.0
    slot_container.offset_bottom = -14.0
    slot_container.offset_left   = -120.0
    slot_container.offset_right  = 120.0
    canvas.add_child(slot_container)

    for i in 3:
        var col: Color = weapon_colors[i]
        var vbox := VBoxContainer.new()
        vbox.add_theme_constant_override("separation", 3)
        slot_container.add_child(vbox)

        var hotkey_lbl := Label.new()
        hotkey_lbl.text = "[%d]" % (i + 1)
        hotkey_lbl.add_theme_font_size_override("font_size", 9)
        hotkey_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
        hotkey_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        vbox.add_child(hotkey_lbl)

        var btn := Button.new()
        btn.text             = weapon_names[i]
        btn.custom_minimum_size = Vector2(72, 52)
        btn.pressed.connect(Callable(self, "_on_slot_pressed").bind(i))
        var sty := StyleBoxFlat.new()
        sty.bg_color          = Color(0, 0, 0, 0)
        sty.border_width_left = sty.border_width_right = \
            sty.border_width_top = sty.border_width_bottom = 2
        sty.border_color = col
        sty.corner_radius_top_left = sty.corner_radius_top_right = \
            sty.corner_radius_bottom_left = sty.corner_radius_bottom_right = 8
        btn.add_theme_stylebox_override("normal",   sty)
        btn.add_theme_stylebox_override("hover",    sty)
        btn.add_theme_stylebox_override("pressed",  sty)
        btn.add_theme_stylebox_override("disabled", sty)
        btn.add_theme_color_override("font_color",          col)
        btn.add_theme_color_override("font_disabled_color", Color(col.r, col.g, col.b, 0.3))
        btn.add_theme_font_size_override("font_size", 9)
        vbox.add_child(btn)
        slot_buttons.append(btn)

        var cd_fill := ColorRect.new()
        cd_fill.color = col
        cd_fill.custom_minimum_size = Vector2(0, 3)
        cd_fill.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
        btn.add_child(cd_fill)
        slot_cooldowns.append(cd_fill)

    # ── Top-center: tractor beam toggle ──────────────────────────────────────
    tractor_button = Button.new()
    tractor_button.text = "TRACTOR"
    tractor_button.set_anchors_preset(Control.PRESET_TOP_WIDE)
    tractor_button.anchor_left   = 0.5
    tractor_button.anchor_right  = 0.5
    tractor_button.offset_left   = -55.0
    tractor_button.offset_right  = 55.0
    tractor_button.offset_top    = 12.0
    tractor_button.offset_bottom = 36.0
    tractor_button.pressed.connect(_on_tractor_pressed)
    var tst := StyleBoxFlat.new()
    tst.bg_color      = Color(0.961, 0.773, 0.259, 0.1)
    tst.border_width_left = tst.border_width_right = \
        tst.border_width_top = tst.border_width_bottom = 2
    tst.border_color  = Color(0.961, 0.773, 0.259)
    tst.corner_radius_top_left = tst.corner_radius_top_right = \
        tst.corner_radius_bottom_left = tst.corner_radius_bottom_right = 12
    tractor_button.add_theme_stylebox_override("normal",  tst)
    tractor_button.add_theme_stylebox_override("hover",   tst)
    tractor_button.add_theme_stylebox_override("pressed", tst)
    tractor_button.add_theme_color_override("font_color", Color(0.961, 0.773, 0.259))
    tractor_button.add_theme_font_size_override("font_size", 9)
    canvas.add_child(tractor_button)

    # ── Top-right: mass + cargo cluster ──────────────────────────────────────
    var tr_vbox := VBoxContainer.new()
    tr_vbox.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    tr_vbox.anchor_left   = 1.0
    tr_vbox.anchor_right  = 1.0
    tr_vbox.offset_left   = -110.0
    tr_vbox.offset_right  = -12.0
    tr_vbox.offset_top    = 12.0
    tr_vbox.offset_bottom = 60.0
    tr_vbox.alignment     = BoxContainer.ALIGNMENT_END
    canvas.add_child(tr_vbox)

    mass_label = Label.new()
    mass_label.add_theme_font_size_override("font_size", 14)
    mass_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
    mass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    tr_vbox.add_child(mass_label)

    cargo_bar_bg = ColorRect.new()
    cargo_bar_bg.color               = Color(1, 1, 1, 0.07)
    cargo_bar_bg.custom_minimum_size = Vector2(88, 4)
    tr_vbox.add_child(cargo_bar_bg)

    cargo_bar = ColorRect.new()
    cargo_bar.color = Color(0.961, 0.773, 0.259)
    cargo_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
    cargo_bar.anchor_right = 0.0   # updated each frame
    cargo_bar_bg.add_child(cargo_bar)

    cargo_label = Label.new()
    cargo_label.add_theme_font_size_override("font_size", 9)
    cargo_label.add_theme_color_override("font_color", Color(0.961, 0.773, 0.259, 0.7))
    cargo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    tr_vbox.add_child(cargo_label)


func _on_slot_pressed(slot: int) -> void:
    active_weapon = slot


func _on_tractor_pressed() -> void:
    tractor_active = not tractor_active
    if not tractor_active:
        tractor_target = -1
```

- [ ] **Step 4: Replace `_update_fire_button_ui()` with `_update_hud()`**

Delete `_update_fire_button_ui()` entirely. Add:

```gdscript
func _update_hud() -> void:
    if slot_buttons.is_empty():
        return

    var ammo_counts:    Array[int]   = [player_missiles_remaining, player_homing_remaining, player_mine_remaining]
    var ammo_maxes:     Array[int]   = [PLAYER_MAX_MISSILES,       PLAYER_MAX_HOMING,       PLAYER_MAX_MINES]
    var cooldowns:      Array[float] = [player_fire_cooldown,      player_homing_cooldown,   player_mine_cooldown]
    var cd_maxes:       Array[float] = [PLAYER_FIRE_COOLDOWN,      PLAYER_HOMING_COOLDOWN,   PLAYER_MINE_COOLDOWN]

    for i in 3:
        var btn:  Button    = slot_buttons[i]
        var fill: ColorRect = slot_cooldowns[i]
        var is_active := active_weapon == i
        var has_ammo  := ammo_counts[i] > 0
        btn.disabled = phase == GamePhase.ENDED or not player_alive

        # Highlight active slot
        var sty := btn.get_theme_stylebox("normal") as StyleBoxFlat
        if sty:
            sty.bg_color = Color(0.05, 0.05, 0.05, 0.5) if is_active else Color(0, 0, 0, 0)

        # Cooldown fill (left to right as it recovers)
        var cd_ratio: float = 1.0 - clampf(cooldowns[i] / cd_maxes[i], 0.0, 1.0)
        fill.size.x = btn.size.x * cd_ratio

        # Label
        if ammo_counts[i] <= 0:
            btn.text = "EMPTY"
        elif cooldowns[i] > 0.0:
            btn.text = "..."
        else:
            btn.text = "%s ×%d" % [["MSL", "HMG", "MNE"][i], ammo_counts[i]]

    # Tractor button style
    if tractor_button:
        var tst := tractor_button.get_theme_stylebox("normal") as StyleBoxFlat
        if tst:
            tst.bg_color = Color(0.961, 0.773, 0.259, 0.15 if tractor_active else 0.0)
        tractor_button.text = "TRACTOR ●" if tractor_active else "TRACTOR"

    # Mass + cargo
    if mass_label:
        mass_label.text = "MASS  %.0f t" % player_mass
    if cargo_label:
        cargo_label.text = "CARGO %.0f / %.0f t" % [player_cargo_aboard, PLAYER_CARGO_CAP]
    if cargo_bar and cargo_bar_bg:
        var fill_ratio: float = clampf(player_cargo_aboard / PLAYER_CARGO_CAP, 0.0, 1.0)
        cargo_bar.size.x = cargo_bar_bg.size.x * fill_ratio
```

- [ ] **Step 5: Update `_reset_game()` — replace `_update_fire_button_ui()` call**

Find the call to `_update_fire_button_ui()` inside `_reset_game()` and replace it:
```gdscript
if is_node_ready():
    _update_hud()
```

- [ ] **Step 6: Update `_show_end_ui()` to display scrap score on victory**

Replace `_show_end_ui()`:
```gdscript
func _show_end_ui() -> void:
    if end_state == "victory":
        var total_scrap: float = player_cargo_aboard
        # Count any tethered over-capacity scrap
        if tractor_active and tractor_target >= 0 and tractor_target < scrap.size():
            total_scrap += float(scrap[tractor_target].mass)
        message_label.text = "Victory!\nScrap collected: %.0f t" % total_scrap
    elif end_state == "defeat":
        message_label.text = "Defeat!"
    else:
        message_label.text = ""
    message_label.visible  = true
    restart_button.visible = true
```

- [ ] **Step 7: Update `_process()` to call `_update_hud()` instead of `_update_fire_button_ui()`**

```gdscript
func _process(delta: float) -> void:
    if phase == GamePhase.SIMULATING:
        _step_simulation(delta)
    elif phase == GamePhase.ENDED:
        _step_end_timer(delta)

    camera.position = player_pos
    $Renderer.queue_redraw()
    _update_hud()
```

- [ ] **Step 8: Draw HP pips in `game_renderer.gd`**

Add a new draw function:

```gdscript
func _draw_hud_hp() -> void:
    var pip_size:  float = 11.0
    var pip_gap:   float = 3.0
    var origin     := game.camera.get_screen_center_position() - \
                      Vector2(get_viewport_rect().size * 0.5) + Vector2(14.0, 14.0)
    # Convert screen-space to world-space for drawing (renderer uses world coords)
    var world_origin := game.player_pos - get_viewport_rect().size * 0.5 + Vector2(14.0, 14.0)

    for i in game.PLAYER_MAX_HP:
        var cx: float = world_origin.x + float(i) * (pip_size + pip_gap) + pip_size * 0.5
        var cy: float = world_origin.y + pip_size * 0.5
        var filled: bool = i < game.player_hp
        if filled:
            var pts := PackedVector2Array([
                Vector2(cx - pip_size * 0.5, cy - pip_size * 0.5),
                Vector2(cx + pip_size * 0.5, cy - pip_size * 0.5),
                Vector2(cx + pip_size * 0.5, cy + pip_size * 0.5),
                Vector2(cx - pip_size * 0.5, cy + pip_size * 0.5),
            ])
            draw_polygon(pts, PackedColorArray([game.PLAYER_COLOR, game.PLAYER_COLOR,
                                                 game.PLAYER_COLOR, game.PLAYER_COLOR]))
        else:
            draw_rect(Rect2(cx - pip_size * 0.5, cy - pip_size * 0.5, pip_size, pip_size),
                      Color(1, 1, 1, 0.15), false, 1.0)
```

- [ ] **Step 9: Call `_draw_hud_hp()` from `_draw()`**

Add after all other draw calls:
```gdscript
if game.player_alive:
    _draw_hud_hp()
```

- [ ] **Step 10: Remove FireButtonContainer from scene**

In `game_world.tscn`, delete the `FireButtonContainer` node (which contained FireButton, CooldownFill, AmmoDisplay). The new weapon slot buttons are created programmatically and will appear correctly without the scene node.

To do this without directly editing the .tscn: in `_ready()`, find and free the old node:
```gdscript
func _ready() -> void:
    randomize()
    _generate_stars()
    # Remove old fire button container if it still exists in the scene
    var old_container := $CanvasLayer.get_node_or_null("FireButtonContainer")
    if old_container:
        old_container.queue_free()
    _reset_game()
    restart_button.pressed.connect(_on_restart_pressed)
    _build_hud()
```

- [ ] **Step 11: Run the project**

Expected:
- Top-left: white square HP pips
- Top-center: gold TRACTOR toggle button (click or press T to toggle)
- Top-right: ship mass in tonnes, cargo bar, cargo tonnage
- Bottom-center: three weapon slot buttons (red/lime/amber) with ammo count and cooldown strip
- Pressing 1/2/3 highlights the active slot
- Old fire button is gone

- [ ] **Step 10: Commit**

```bash
git add game.gd game_renderer.gd
git commit -m "feat: full HUD rebuild — weapon slots (1/2/3), tractor toggle, mass/cargo cluster, HP pips, scrap score on victory"
```

---

## Task 9: Push & Final Verification

- [ ] **Step 1: Full end-to-end playtest checklist**

Run the project and verify each item:

| # | Check |
|---|---|
| 1 | Player starts white, enemies are red/orange/purple |
| 2 | Mouse moves thrust arrow; dotted path updates in real time |
| 3 | Clicking commits the move — ship drifts then follows thrust |
| 4 | Ships gradually drift toward each other over multiple turns (gravity) |
| 5 | 3 scrap pieces visible at start |
| 6 | Destroying enemy spawns scrap pieces |
| 7 | Pressing T activates tractor beam; gold beam line appears toward nearest scrap |
| 8 | Scrap reels in; player mass increases; turns get wider |
| 9 | Too-heavy scrap: beam turns red, scrap dangles and fights steering |
| 10 | Press 1/2/3 to switch weapons; correct slot highlights |
| 11 | Missile [1]: red thick triangle, fires forward |
| 12 | Homing [2]: lime winged shape, curves toward enemies |
| 13 | Mine [3]: amber spiky circle, drops behind player; arm ring fades; triggers on proximity |
| 14 | Mass label and cargo bar update as scrap is collected |
| 15 | Win/lose conditions still work correctly |

- [ ] **Step 2: Create beads issues for tuning/polish items discovered during playtest**

```bash
bd create --title="Tune physics constants (G_SCALED, MAX_THRUST, TRACTOR_SPRING_K)" \
  --description="Play-feel pass on gravity strength, thrust cap, tractor spring, and mine trigger radius. All constants are in game.gd under their section headers." \
  --type=task --priority=2
```

- [ ] **Step 3: Push**

```bash
git pull --rebase
git push
git status
```

Expected: `Your branch is up to date with 'origin/master'.`

---

## Constants Quick Reference

All new constants are in `game.gd`. Tune during playtesting:

| Constant | Default | Effect |
|---|---|---|
| `PLAYER_MASS` | 10.0 t | Base ship mass |
| `MAX_PLAYER_THRUST` | 1200.0 | Max force — higher = snappier turns |
| `G_SCALED` | 40000.0 | Gravity strength — higher = stronger pulls |
| `GRAVITY_EMIT_MIN_MASS` | 6.0 t | Below this mass, body doesn't emit gravity |
| `TRACTOR_RANGE` | 250.0 px | Beam search radius |
| `TRACTOR_SPRING_K` | 0.2 | Reel-in speed — higher = faster pull |
| `TETHER_LENGTH` | 200.0 px | Max pendulum arm length |
| `PLAYER_CARGO_CAP` | 4.0 t | Max absorbable scrap |
| `MINE_ARM_TIME` | 1.0 s | Arming delay |
| `MINE_TRIGGER_RADIUS` | 40.0 px | Proximity detection |
| `HOMING_TURN_RATE` | 1.2 rad/s | Homing aggressiveness |
