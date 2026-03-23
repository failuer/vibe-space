# Enemy AI Design Spec

**Date:** 2026-03-23
**Project:** vibe-space (Godot 4.5 top-down space shooter)

---

## Overview

Replace the current placeholder enemy AI with a real-time, archetype-based system featuring three distinct enemy personalities. The architecture is explicitly designed for extensibility: adding a new enemy type requires one new file and one new line in `game.gd`.

---

## Design Decisions

| Question | Decision |
|---|---|
| Steering model | Real-time — enemies steer every `game_delta` step during simulation |
| Enemy variety | 3 archetypes: Aggressor, Orbiter, Flanker |
| Self-preservation | Per-archetype — each type handles missile evasion differently |
| Extensibility | Static-function interface in separate files; `match` dispatcher in `game.gd` |

---

## Architecture

### New Files

```
aggressor_ai.gd
orbiter_ai.gd
flanker_ai.gd
```

All three live alongside `game.gd` at the project root.

### Interface Contract

Each archetype file exposes three static functions. GDScript duck-typing enforces this informally; the dispatcher calls them by name.

```gdscript
# Required in every archetype file:

static func steer(enemy: Dictionary, game: Game, game_delta: float) -> Vector2
# Returns the desired velocity for this frame (direction * speed, fully scaled).
# Also performs per-frame ai_state updates (e.g. decrementing timers).
# game_delta is the time-scaled delta from _step_simulation — use this, not raw delta.

static func should_fire(enemy: Dictionary, game: Game) -> bool
# Returns true if this enemy wants to fire this frame.
# game.gd's _try_fire_enemy() checks cooldown and ammo before actually firing.

static func evade_missile(enemy: Dictionary, missile_pos: Vector2, missile_vel: Vector2, game_delta: float) -> Vector2
# Returns a one-frame velocity impulse to add when a player missile is within EVASION_DETECT_RADIUS.
# Return Vector2.ZERO to skip evasion. Also permitted to mutate enemy.ai_state.
# game_delta is the same time-scaled delta passed to steer().
```

### Game Properties Accessed by Archetypes

Archetype scripts may only read the following properties from the `game` parameter:

```
game.player_pos     : Vector2
game.player_vel     : Vector2
game.player_alive   : bool
game.ENEMY_RADIUS   : float   # needed for spawn offset in _try_fire_enemy; access from game.gd not archetype files
game.MISSILE_RADIUS : float   # same
```

No other `game.*` properties should be accessed from archetype files.

### Enemy Dictionary — New Keys

Two keys are added to every enemy dict at spawn:

```gdscript
"archetype": String      # "aggressor" | "orbiter" | "flanker"
"ai_state": Dictionary   # archetype-owned scratchpad, initialized at spawn
```

All existing keys (`pos`, `vel`, `alive`, `hp`, `missiles_remaining`, `fire_cooldown`) are unchanged.

### Dispatcher in `game.gd`

```gdscript
const AggressorAI = preload("res://aggressor_ai.gd")
const OrbiterAI   = preload("res://orbiter_ai.gd")
const FlankerAI   = preload("res://flanker_ai.gd")

func _get_ai(archetype: String) -> GDScript:
    match archetype:
        "aggressor": return AggressorAI
        "orbiter":   return OrbiterAI
        "flanker":   return FlankerAI
    return AggressorAI  # fallback
```

Returning `GDScript` (the static type) from `_get_ai` avoids per-frame untyped-call warnings in Godot 4.5.

**Execution order inside `_step_simulation()`:**

```gdscript
if game_delta > 0.0:
    # 1. Tick cooldowns (move here if currently after _integrate_motion)
    for enemy in enemies:
        if enemy.alive and (enemy.fire_cooldown as float) > 0.0:
            enemy.fire_cooldown = maxf(0.0, (enemy.fire_cooldown as float) - game_delta)

    # 2. AI dispatcher — runs after cooldown tick, before integration
    for enemy in enemies:
        if not enemy.alive:
            continue
        var ai := _get_ai(enemy.archetype)

        # Steering — sets velocity for this frame
        enemy.vel = ai.steer(enemy, self, game_delta)

        # Firing — archetype decides intent; _try_fire_enemy checks cooldown/ammo
        if ai.should_fire(enemy, self):
            _try_fire_enemy(enemy)

        # Evasion — only the single nearest player missile within range triggers evasion
        var nearest_missile = null
        var nearest_dist    = EVASION_DETECT_RADIUS
        for missile in missiles:
            if missile.from_player:
                var d = (missile.pos as Vector2).distance_to(enemy.pos as Vector2)
                if d < nearest_dist:
                    nearest_dist    = d
                    nearest_missile = missile
        if nearest_missile != null:
            enemy.vel += ai.evade_missile(enemy, nearest_missile.pos, nearest_missile.vel, game_delta)

    # 3. Integration — uses velocities set by AI dispatcher
    _integrate_motion(game_delta)
    # ... rest of simulation (collisions, etc.)
```

Only the **nearest** player missile triggers evasion per enemy per frame (prevents stacking impulses from multiple simultaneous missiles).

### New Helper: `_try_fire_enemy(enemy)`

Extract the per-enemy firing logic from `_step_enemy_firing()`. The missile always aims toward `player_pos`. The missile spawn position is offset forward by `ENEMY_RADIUS + MISSILE_RADIUS + 2.0` (matching the existing `_step_enemy_firing` offset) to avoid immediate collision:

```gdscript
func _try_fire_enemy(enemy: Dictionary) -> void:
    if (enemy.fire_cooldown as float) > 0.0:
        return
    if (enemy.missiles_remaining as int) <= 0:
        return
    var aim_dir := (player_pos - (enemy.pos as Vector2)).normalized()
    if aim_dir == Vector2.ZERO:
        return  # on top of player, skip
    var spawn_pos := (enemy.pos as Vector2) + aim_dir * (ENEMY_RADIUS + MISSILE_RADIUS + 2.0)
    var m := {
        "pos":         spawn_pos,
        "vel":         aim_dir * MISSILE_SPEED,   # reuse existing MISSILE_SPEED constant
        "from_player": false,
        "power":       MISSILE_POWER,
    }
    missiles.append(m)
    enemy.fire_cooldown      = ENEMY_FIRE_COOLDOWN
    enemy.missiles_remaining = (enemy.missiles_remaining as int) - 1
```

`MISSILE_SPEED` is the existing shared constant (used by both player and enemy missiles). No new speed constant is needed.

**Remove `_step_enemy_firing()` and its call from `_step_simulation()` entirely.** The dispatcher now owns all enemy firing. Keeping both would double-fire every frame.

### New Constants in `game.gd`

```gdscript
const EVASION_DETECT_RADIUS := 80.0   # px — missile proximity that triggers evasion
```

All other constants referenced by `_try_fire_enemy` (`MISSILE_SPEED`, `MISSILE_POWER`, `ENEMY_FIRE_COOLDOWN`, `ENEMY_RADIUS`, `MISSILE_RADIUS`) already exist or are extracted from `_step_enemy_firing()` when it is removed.

### Spawn Assignment

The three existing enemy slots map to archetypes by index:

```gdscript
const ARCHETYPE_ROSTER := ["aggressor", "orbiter", "flanker"]
# enemy index 0 -> aggressor, 1 -> orbiter, 2 -> flanker

# At spawn, set archetype and initial ai_state:
var archetype := ARCHETYPE_ROSTER[i % ARCHETYPE_ROSTER.size()]
var initial_ai_state: Dictionary
match archetype:
    "aggressor": initial_ai_state = {}
    "orbiter":   initial_ai_state = { "orbit_dir": 1, "evade_timer": 0.0 }
    "flanker":   initial_ai_state = {}
enemy["archetype"] = archetype
enemy["ai_state"]  = initial_ai_state
```

---

## Archetype Specifications

### Aggressor (`aggressor_ai.gd`)

**Personality:** Charges straight at the player. Fearless — never evades. High pressure up close.

**Constants:**
```gdscript
const SPEED       := 180.0   # px/s
const FIRE_RANGE  := 120.0   # px — fires when this close
```

**`ai_state` at spawn:** `{}` (unused)

**`steer`:**
```gdscript
var to_player = game.player_pos - (enemy.pos as Vector2)
# Edge case: if enemy is exactly on player, normalized() returns ZERO — acceptable, they will collide.
return to_player.normalized() * SPEED
```

**`should_fire`:** `return (enemy.pos as Vector2).distance_to(game.player_pos) < FIRE_RANGE`

**`evade_missile`:** `return Vector2.ZERO`

---

### Orbiter (`orbiter_ai.gd`)

**Personality:** Maintains a target orbit radius around the player, circling continuously and firing at all times. Briefly reverses orbit direction when a missile gets close.

**Constants:**
```gdscript
const SPEED            := 140.0   # px/s
const ORBIT_RADIUS     := 250.0   # px — target distance from player
const RADIAL_STRENGTH  := 0.6     # blend toward orbit radius vs. tangential circle
const EVADE_DURATION   := 0.4     # seconds to reverse orbit direction on dodge
const EVADE_NUDGE      := 40.0    # px/s immediate lateral impulse when evading
```

**`ai_state` at spawn:** `{ "orbit_dir": 1, "evade_timer": 0.0 }`

**`steer`:**
```gdscript
# Decrement evade timer; restore orbit_dir when it expires
if enemy.ai_state.evade_timer > 0.0:
    enemy.ai_state.evade_timer -= game_delta
    if enemy.ai_state.evade_timer <= 0.0:
        enemy.ai_state.evade_timer = 0.0
        enemy.ai_state.orbit_dir  *= -1  # flip back to original direction

var to_player = game.player_pos - (enemy.pos as Vector2)
var dist      = to_player.length()
if dist < 0.001:
    return Vector2.ZERO

var radial  = to_player / dist                                              # normalized toward player
var tangent = Vector2(-radial.y, radial.x) * enemy.ai_state.orbit_dir      # perpendicular

# Blend: correct distance radially, circle tangentially
var correction = clamp((dist - ORBIT_RADIUS) / ORBIT_RADIUS, -1.0, 1.0)
var desired    = radial * correction * RADIAL_STRENGTH + tangent * (1.0 - RADIAL_STRENGTH)
return desired.normalized() * SPEED
```

**`should_fire`:** `return true` (always — `_try_fire_enemy` rate-limits via cooldown)

**`evade_missile`:**
```gdscript
# Guard: only flip orbit_dir if not already evading (prevents per-frame jitter)
if enemy.ai_state.evade_timer <= 0.0:
    enemy.ai_state.orbit_dir  *= -1
    enemy.ai_state.evade_timer = EVADE_DURATION

# Return a small immediate lateral nudge away from missile path
var missile_dir_norm = missile_vel.normalized()
var perp = Vector2(-missile_dir_norm.y, missile_dir_norm.x)
var side = sign(perp.dot((enemy.pos as Vector2) - missile_pos))
if side == 0.0: side = float(enemy.ai_state.orbit_dir)
return perp * side * EVADE_NUDGE
```

---

### Flanker (`flanker_ai.gd`)

**Personality:** Steers to get directly behind the player (opposite their velocity). Fires only when in position and within range. Full lateral dodge on missile detection.

**Constants:**
```gdscript
const SPEED           := 160.0   # px/s
const FLANK_DISTANCE  := 180.0   # px behind player to target
const FIRE_ANGLE      := 30.0    # degrees — fire arc when behind player
const FIRE_RANGE      := 200.0   # px — max distance to fire (prevents wasted ammo at extreme range)
const EVADE_STRENGTH  := 220.0   # px/s lateral impulse on missile dodge
```

**`ai_state` at spawn:** `{}` (stateless — reapproach happens naturally after dodge)

**`steer`:**
```gdscript
var behind_dir: Vector2
if game.player_vel.length() > 1.0:
    behind_dir = -game.player_vel.normalized()
else:
    # Player nearly stopped — approach from opposite side of current position
    var to_player = game.player_pos - (enemy.pos as Vector2)
    behind_dir = -to_player.normalized() if to_player.length() > 0.001 else Vector2.UP

var target_pos = game.player_pos + behind_dir * FLANK_DISTANCE
var to_target  = target_pos - (enemy.pos as Vector2)
if to_target.length() < 0.001:
    return Vector2.ZERO
return to_target.normalized() * SPEED
```

**`should_fire`:**
```gdscript
if game.player_vel.length() <= 1.0:
    return false  # can't determine behind-direction; don't fire

# Must be within firing range
if (enemy.pos as Vector2).distance_to(game.player_pos) > FIRE_RANGE:
    return false

# Must be positioned in the arc behind the player
var from_player_to_enemy = ((enemy.pos as Vector2) - game.player_pos).normalized()
var behind_facing        = -game.player_vel.normalized()
var angle_deg            = rad_to_deg(acos(clamp(from_player_to_enemy.dot(behind_facing), -1.0, 1.0)))
return angle_deg < FIRE_ANGLE
```

**`evade_missile`:**
```gdscript
# Lateral impulse perpendicular to missile velocity, toward the safer side
var missile_dir_norm = missile_vel.normalized()
var perp = Vector2(-missile_dir_norm.y, missile_dir_norm.x)
var side = sign(perp.dot((enemy.pos as Vector2) - missile_pos))
if side == 0.0: side = 1.0
return perp * side * EVADE_STRENGTH
# steer() naturally reapproaches from the new angle — no extra state needed.
```

---

## Integration Points in `game.gd` — Step by Step

1. **Preload:** Add three `const` preloads at the top of `game.gd`.
2. **New constant:** Add `EVASION_DETECT_RADIUS := 80.0`.
3. **Spawn:** When creating enemy dicts, add `"archetype"` and `"ai_state"` as shown in Spawn Assignment above.
4. **Move cooldown tick:** If the existing enemy cooldown decrement runs after `_integrate_motion`, move it to run first inside `if game_delta > 0.0:`, before the AI dispatcher.
5. **Insert AI dispatcher:** After cooldown tick, before `_integrate_motion`. See full dispatcher snippet above.
6. **Add `_try_fire_enemy`:** New helper function as specified above.
7. **Remove `_step_enemy_firing()`:** Delete the function and its call from `_step_simulation()`. All enemy firing now goes through the dispatcher → `_try_fire_enemy`.
8. **No changes** to renderer, collision, HP, explosion, or debris systems.

---

## Extensibility Guide

To add a new enemy type (e.g., "sniper"):

1. Create `sniper_ai.gd` with the three static functions (`steer`, `should_fire`, `evade_missile`).
2. Add `"sniper": return SniperAI` to `_get_ai()` in `game.gd`.
3. Add `"sniper"` to `ARCHETYPE_ROSTER` and handle its `ai_state` initialization in the spawn match block.

No other files change.

---

## Out of Scope

- Wave/difficulty progression (which archetypes spawn when)
- Formation coordination between enemies
- Enemy HP scaling per archetype
- Animated archetype-specific visuals (different ship shapes)
