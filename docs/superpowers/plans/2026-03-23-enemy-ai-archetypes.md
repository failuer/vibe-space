# Enemy AI Archetypes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the dummy enemy AI with three distinct archetypes (Aggressor, Orbiter, Flanker) that steer in real-time every frame, each with unique movement, firing, and missile-evasion behaviors.

**Architecture:** Each archetype lives in its own GDScript file exposing three static functions (`steer`, `should_fire`, `evade_missile`). `game.gd` dispatches to the right archetype via a one-line `match` on `enemy.archetype`. Adding a new enemy type means adding one file and one `match` branch — nothing else changes.

**Tech Stack:** Godot 4.5, GDScript, manual physics (no Godot physics engine), Dictionary-based game objects.

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `aggressor_ai.gd` | Charges at player; fearless; fires close-range |
| Create | `orbiter_ai.gd` | Circles at orbit radius; fires always; reverses orbit on dodge |
| Create | `flanker_ai.gd` | Gets behind player; fires from blind spot; lateral dodge |
| Modify | `game.gd:56–58` | Add `EVASION_DETECT_RADIUS` constant |
| Modify | `game.gd:102` | Add `ARCHETYPE_ROSTER` constant |
| Modify | `game.gd:172–197` | Add `archetype`/`ai_state` keys to enemy dicts at spawn |
| Modify | `game.gd:262–286` | Reorder simulation step: cooldowns → AI dispatcher → integrate |
| Modify | `game.gd:302–332` | Remove `_step_enemy_firing()` (replaced by dispatcher + `_try_fire_enemy`) |
| Modify | `game.gd` (top) | Add three `const` preloads and `_get_ai()` dispatcher helper |

---

## How to verify (no test framework)

This is a Godot game with no unit test framework. Each task ends with a verification step:
- Open the project in Godot 4.5 editor
- Press **F5** (or the Play ▶ button) to run
- Check the **Output** panel at the bottom for errors/warnings
- Observe in-game behavior as described

If Godot shows a parse error, fix it before continuing. Parse errors appear in red in the Output panel even before you press play.

---

## Task 1: Add archetype and ai_state keys to enemy spawn

This wires up the data model. No AI logic yet — enemies will have the new keys but still drift (the dispatcher isn't connected yet).

**Files:**
- Modify: `game.gd:56–58` (constants area near `ENEMY_FIRE_ANGLE_THRESHOLD`)
- Modify: `game.gd:172–197` (enemy spawn in `_reset_game()`)

- [ ] **Step 1: Add `EVASION_DETECT_RADIUS` constant and `ARCHETYPE_ROSTER`**

In `game.gd`, after line 58 (`const ENEMY_FIRE_ANGLE_THRESHOLD := PI / 4.0`), add:

```gdscript
const EVASION_DETECT_RADIUS := 80.0   # px — missile proximity triggering evasion
const ARCHETYPE_ROSTER := ["aggressor", "orbiter", "flanker"]
```

- [ ] **Step 2: Add a helper to produce initial ai_state per archetype**

Add this function anywhere in `game.gd` (e.g., just before `_reset_game()`):

```gdscript
func _make_ai_state(archetype: String) -> Dictionary:
    match archetype:
        "orbiter": return { "orbit_dir": 1, "evade_timer": 0.0 }
        _:         return {}
```

- [ ] **Step 3: Update the three enemy dicts in `_reset_game()` (lines 172–197)**

Replace the entire enemy setup block with:

```gdscript
    # Enemy setup — each slot maps to an archetype in ARCHETYPE_ROSTER
    enemies.clear()
    var enemy_spawns := [
        { "pos": Vector2(300.0, 0.0),    "vel": Vector2.LEFT  * ENEMY_SPEED },
        { "pos": Vector2(-250.0, -150.0), "vel": Vector2.RIGHT * ENEMY_SPEED },
        { "pos": Vector2(0.0, 250.0),    "vel": Vector2.UP    * ENEMY_SPEED },
    ]
    for i in enemy_spawns.size():
        var archetype := ARCHETYPE_ROSTER[i % ARCHETYPE_ROSTER.size()]
        enemies.append({
            "pos":               enemy_spawns[i].pos,
            "vel":               enemy_spawns[i].vel,
            "alive":             true,
            "missiles_remaining": ENEMY_MAX_MISSILES,
            "fire_cooldown":     0.0,
            "hp":                ENEMY_MAX_HP,
            "archetype":         archetype,
            "ai_state":          _make_ai_state(archetype),
        })
```

- [ ] **Step 4: Verify — run the game, check Output for errors**

Press F5. The game should open exactly as before (enemies still drift, no new behavior). In the Output panel, confirm zero parse errors and zero runtime errors on startup.

- [ ] **Step 5: Commit**

```bash
git add game.gd
git commit -m "feat: add archetype and ai_state keys to enemy spawn data"
```

---

## Task 2: Add `_try_fire_enemy()` helper and remove `_step_enemy_firing()`

Extracts the firing logic into a callable helper. The dispatcher (Task 6) will call it. Removing `_step_enemy_firing` prevents double-firing once the dispatcher is wired up.

**Files:**
- Modify: `game.gd:302–332` (remove `_step_enemy_firing`)
- Modify: `game.gd:282` (remove the call to `_step_enemy_firing`)
- Add new function `_try_fire_enemy` anywhere in `game.gd`

- [ ] **Step 1: Add `_try_fire_enemy(enemy)` function**

Add this function to `game.gd` (place it near `_try_fire_player` for readability):

```gdscript
func _try_fire_enemy(enemy: Dictionary) -> void:
    if (enemy.fire_cooldown as float) > 0.0:
        return
    if (enemy.missiles_remaining as int) <= 0:
        return
    var aim_dir := (player_pos - (enemy.pos as Vector2)).normalized()
    if aim_dir == Vector2.ZERO:
        return  # enemy is exactly on player — skip
    var spawn_pos := (enemy.pos as Vector2) + aim_dir * (ENEMY_RADIUS + MISSILE_RADIUS + 2.0)
    missiles.append({
        "pos":         spawn_pos,
        "vel":         aim_dir * MISSILE_SPEED,
        "from_player": false,
        "power":       MISSILE_POWER,
    })
    enemy.missiles_remaining = (enemy.missiles_remaining as int) - 1
    enemy.fire_cooldown      = ENEMY_FIRE_COOLDOWN
```

- [ ] **Step 2: Remove `_step_enemy_firing()` function (lines 302–332)**

Delete the entire `_step_enemy_firing` function from `game.gd`. It is:

```gdscript
func _step_enemy_firing(_delta: float) -> void:
    ...
```

- [ ] **Step 3: Remove the call to `_step_enemy_firing` in `_step_simulation()`**

In `_step_simulation()`, delete line 282:

```gdscript
        _step_enemy_firing(game_delta)   # DELETE THIS LINE
```

**Note:** After this step, enemies will have no firing logic temporarily (until the dispatcher is added in Task 6). This is intentional and expected.

- [ ] **Step 4: Verify — run the game, check Output for errors**

Press F5. The game should run without errors. Enemies will no longer fire (that's expected — the dispatcher isn't wired yet). Confirm zero parse errors in Output.

- [ ] **Step 5: Commit**

```bash
git add game.gd
git commit -m "refactor: replace _step_enemy_firing with _try_fire_enemy helper"
```

---

## Task 3: Create `aggressor_ai.gd`

The simplest archetype. Charges straight at the player. Never evades. Fires when close.

**Files:**
- Create: `aggressor_ai.gd`

- [ ] **Step 1: Create `aggressor_ai.gd` with complete implementation**

```gdscript
# aggressor_ai.gd
# Charges straight at the player. Fearless — never evades. High pressure up close.

const SPEED      := 180.0  # px/s
const FIRE_RANGE := 120.0  # px — fires when within this distance

static func steer(enemy: Dictionary, game: Game, _game_delta: float) -> Vector2:
    var to_player := game.player_pos - (enemy.pos as Vector2)
    # If exactly on player, normalized() returns ZERO — acceptable, they'll collide.
    return to_player.normalized() * SPEED

static func should_fire(enemy: Dictionary, game: Game) -> bool:
    return (enemy.pos as Vector2).distance_to(game.player_pos) < FIRE_RANGE

static func evade_missile(_enemy: Dictionary, _missile_pos: Vector2, _missile_vel: Vector2, _game_delta: float) -> Vector2:
    return Vector2.ZERO  # fearless — never evades
```

- [ ] **Step 2: Verify file syntax**

Open `aggressor_ai.gd` in the Godot editor. The script editor should show no red error indicators. If there are parse errors, they appear in the Output panel when the file is opened.

- [ ] **Step 3: Commit**

```bash
git add aggressor_ai.gd
git commit -m "feat: add Aggressor archetype AI (charges, no evasion)"
```

---

## Task 4: Create `orbiter_ai.gd`

Circles the player at a target orbit radius, fires continuously, reverses orbit direction to dodge missiles.

**Files:**
- Create: `orbiter_ai.gd`

- [ ] **Step 1: Create `orbiter_ai.gd` with complete implementation**

```gdscript
# orbiter_ai.gd
# Circles the player at a target orbit radius. Fires continuously.
# Reverses orbit direction briefly when a player missile gets close.

const SPEED           := 140.0  # px/s
const ORBIT_RADIUS    := 250.0  # px — target distance from player
const RADIAL_STRENGTH := 0.6    # blend: how hard to correct distance vs. circle tangentially
const EVADE_DURATION  := 0.4    # seconds to hold the reversed orbit direction
const EVADE_NUDGE     := 40.0   # px/s immediate lateral impulse when evasion triggers

static func steer(enemy: Dictionary, game: Game, game_delta: float) -> Vector2:
    # Decrement evade timer; flip orbit_dir back when it expires
    if (enemy.ai_state.evade_timer as float) > 0.0:
        enemy.ai_state.evade_timer = (enemy.ai_state.evade_timer as float) - game_delta
        if (enemy.ai_state.evade_timer as float) <= 0.0:
            enemy.ai_state.evade_timer = 0.0
            enemy.ai_state.orbit_dir   = -(enemy.ai_state.orbit_dir as int)  # flip back

    var to_player := game.player_pos - (enemy.pos as Vector2)
    var dist      := to_player.length()
    if dist < 0.001:
        return Vector2.ZERO  # on top of player — avoid zero-vector normalization

    var radial  := to_player / dist                                                      # toward player
    var tangent := Vector2(-radial.y, radial.x) * (enemy.ai_state.orbit_dir as int)     # perpendicular

    # Blend: push toward orbit radius radially, circle tangentially
    var correction := clamp((dist - ORBIT_RADIUS) / ORBIT_RADIUS, -1.0, 1.0)
    var desired    := radial * correction * RADIAL_STRENGTH + tangent * (1.0 - RADIAL_STRENGTH)
    if desired.length() < 0.001:
        return tangent * SPEED
    return desired.normalized() * SPEED

static func should_fire(_enemy: Dictionary, _game: Game) -> bool:
    return true  # always wants to fire; _try_fire_enemy rate-limits via fire_cooldown

static func evade_missile(enemy: Dictionary, missile_pos: Vector2, missile_vel: Vector2, _game_delta: float) -> Vector2:
    # Only trigger evasion if not already evading (prevents per-frame jitter)
    if (enemy.ai_state.evade_timer as float) <= 0.0:
        enemy.ai_state.orbit_dir   = -(enemy.ai_state.orbit_dir as int)  # flip direction
        enemy.ai_state.evade_timer = EVADE_DURATION

    # Small immediate lateral nudge away from missile path
    var missile_norm := missile_vel.normalized()
    var perp         := Vector2(-missile_norm.y, missile_norm.x)
    var side         := sign(perp.dot((enemy.pos as Vector2) - missile_pos))
    if side == 0.0:
        side = float(enemy.ai_state.orbit_dir as int)
    return perp * side * EVADE_NUDGE
```

- [ ] **Step 2: Verify file syntax**

Open `orbiter_ai.gd` in the Godot editor. Confirm no parse errors in Output panel.

- [ ] **Step 3: Commit**

```bash
git add orbiter_ai.gd
git commit -m "feat: add Orbiter archetype AI (orbits, reverses on dodge)"
```

---

## Task 5: Create `flanker_ai.gd`

Steers to the position behind the player (opposite velocity direction). Only fires when in position and within range. Full lateral dodge on missile detection.

**Files:**
- Create: `flanker_ai.gd`

- [ ] **Step 1: Create `flanker_ai.gd` with complete implementation**

```gdscript
# flanker_ai.gd
# Steers to position directly behind the player (opposite to player velocity).
# Only fires when in the blind spot and within range.
# Dodges missiles with a full lateral impulse.

const SPEED          := 160.0  # px/s
const FLANK_DISTANCE := 180.0  # px — how far behind the player to target
const FIRE_ANGLE     := 30.0   # degrees — firing arc when behind player
const FIRE_RANGE     := 200.0  # px — max range to fire (avoids wasting ammo)
const EVADE_STRENGTH := 220.0  # px/s lateral impulse when dodging a missile

static func steer(enemy: Dictionary, game: Game, _game_delta: float) -> Vector2:
    var behind_dir: Vector2
    if game.player_vel.length() > 1.0:
        behind_dir = -game.player_vel.normalized()
    else:
        # Player nearly stopped — approach from the opposite side of current position
        var to_player := game.player_pos - (enemy.pos as Vector2)
        if to_player.length() > 0.001:
            behind_dir = -to_player.normalized()
        else:
            behind_dir = Vector2.UP

    var target_pos := game.player_pos + behind_dir * FLANK_DISTANCE
    var to_target  := target_pos - (enemy.pos as Vector2)
    if to_target.length() < 0.001:
        return Vector2.ZERO
    return to_target.normalized() * SPEED

static func should_fire(enemy: Dictionary, game: Game) -> bool:
    # Can't fire if player velocity is near zero (can't determine "behind")
    if game.player_vel.length() <= 1.0:
        return false

    # Must be close enough to bother firing
    if (enemy.pos as Vector2).distance_to(game.player_pos) > FIRE_RANGE:
        return false

    # Must be positioned in the arc behind the player
    var from_player_to_enemy := ((enemy.pos as Vector2) - game.player_pos).normalized()
    var behind_facing        := -game.player_vel.normalized()
    var dot                  := clamp(from_player_to_enemy.dot(behind_facing), -1.0, 1.0)
    var angle_deg            := rad_to_deg(acos(dot))
    return angle_deg < FIRE_ANGLE

static func evade_missile(enemy: Dictionary, missile_pos: Vector2, missile_vel: Vector2, _game_delta: float) -> Vector2:
    # Full lateral impulse perpendicular to missile velocity, toward the safer side
    var missile_norm := missile_vel.normalized()
    var perp         := Vector2(-missile_norm.y, missile_norm.x)
    var side         := sign(perp.dot((enemy.pos as Vector2) - missile_pos))
    if side == 0.0:
        side = 1.0
    return perp * side * EVADE_STRENGTH
    # steer() will naturally reapproach from the new angle — no extra state needed
```

- [ ] **Step 2: Verify file syntax**

Open `flanker_ai.gd` in the Godot editor. Confirm no parse errors in Output panel.

- [ ] **Step 3: Commit**

```bash
git add flanker_ai.gd
git commit -m "feat: add Flanker archetype AI (blind spot, lateral dodge)"
```

---

## Task 6: Wire the AI dispatcher in `game.gd`

This is the final wiring step. It adds preloads, `_get_ai()`, and the dispatcher block inside `_step_simulation()`. After this task, all three archetypes will be live.

**Files:**
- Modify: `game.gd` (top — preloads)
- Modify: `game.gd` (add `_get_ai()` function)
- Modify: `game.gd:262–286` (reorder `_step_simulation()` and insert dispatcher)

- [ ] **Step 1: Add preloads at the top of `game.gd`**

After line 2 (`class_name Game`), add:

```gdscript
const AggressorAI = preload("res://aggressor_ai.gd")
const OrbiterAI   = preload("res://orbiter_ai.gd")
const FlankerAI   = preload("res://flanker_ai.gd")
```

- [ ] **Step 2: Add `_get_ai()` dispatcher helper**

Add this function anywhere in `game.gd` (e.g., just before `_step_simulation`):

```gdscript
func _get_ai(archetype: String) -> GDScript:
    match archetype:
        "aggressor": return AggressorAI
        "orbiter":   return OrbiterAI
        "flanker":   return FlankerAI
    return AggressorAI  # fallback for unknown archetypes
```

Returning `GDScript` (not just `Object`) prevents per-frame untyped-call warnings in Godot 4.5.

- [ ] **Step 3: Rewrite the `if game_delta > 0.0:` block in `_step_simulation()`**

The current block (lines 274–286) is:

```gdscript
    if game_delta > 0.0:
        _integrate_motion(game_delta)
        # Tick weapon cooldowns ...
        if player_fire_cooldown > 0.0:
            player_fire_cooldown = maxf(0.0, player_fire_cooldown - game_delta)
        for enemy in enemies:
            if enemy.alive and enemy.fire_cooldown > 0.0:
                enemy.fire_cooldown = maxf(0.0, enemy.fire_cooldown - game_delta)
        _step_enemy_firing(game_delta)   # already removed in Task 2
        _handle_collisions()
        _step_explosions(game_delta)
        _check_leave_play_area()
        _cull_offscreen_objects()
```

Replace it with this reordered version (cooldowns → AI → integrate):

```gdscript
    if game_delta > 0.0:
        # 1. Tick weapon cooldowns (before AI so should_fire sees current cooldown)
        if player_fire_cooldown > 0.0:
            player_fire_cooldown = maxf(0.0, player_fire_cooldown - game_delta)
        for enemy in enemies:
            if enemy.alive and (enemy.fire_cooldown as float) > 0.0:
                enemy.fire_cooldown = maxf(0.0, (enemy.fire_cooldown as float) - game_delta)

        # 2. AI dispatcher — steer, fire, evade (only while player is alive)
        if player_alive:
            for enemy in enemies:
                if not enemy.alive:
                    continue
                var ai := _get_ai(enemy.archetype)

                # Steering sets velocity for this frame
                enemy.vel = ai.steer(enemy, self, game_delta)

                # Firing — archetype decides intent; _try_fire_enemy checks cooldown/ammo
                if ai.should_fire(enemy, self):
                    _try_fire_enemy(enemy)

                # Evasion — only the single nearest player missile within range
                var nearest_missile = null
                var nearest_dist    := EVASION_DETECT_RADIUS
                for missile in missiles:
                    if missile.from_player:
                        var d := (missile.pos as Vector2).distance_to(enemy.pos as Vector2)
                        if d < nearest_dist:
                            nearest_dist    = d
                            nearest_missile = missile
                if nearest_missile != null:
                    enemy.vel += ai.evade_missile(
                        enemy,
                        nearest_missile.pos as Vector2,
                        nearest_missile.vel as Vector2,
                        game_delta
                    )

        # 3. Physics integration (uses velocities set by AI dispatcher)
        _integrate_motion(game_delta)
        _handle_collisions()
        _step_explosions(game_delta)
        _check_leave_play_area()
        _cull_offscreen_objects()
```

- [ ] **Step 4: Verify — check Output for parse errors before running**

Save `game.gd`. In the Godot editor, the script editor should show no red markers. Check Output for parse errors.

- [ ] **Step 5: Run the game and verify each archetype**

Press F5. Observe:

**Enemy 0 (Aggressor — top-right):** Should charge directly at the player. Should fire when it gets within ~120px. Should not dodge missiles.

**Enemy 1 (Orbiter — top-left):** Should circle around the player at roughly 250px distance. Should fire continuously (rate-limited by cooldown). When you fire a missile at it, it should briefly change orbit direction.

**Enemy 2 (Flanker — bottom):** Should arc around to get behind the player. Once behind, it should fire. When you fire a missile at it, it should dodge sideways.

Check Output for runtime errors. Common issues and fixes:
- `Invalid call to function 'steer'` → check preload paths match exact filenames
- `Invalid get index 'archetype'` → enemy dict is missing the key (Task 1 not complete or reset game to pick up new spawn)
- `Invalid get index 'orbit_dir'` → `ai_state` is empty `{}` for an orbiter enemy (Task 1 spawn table is wrong)

- [ ] **Step 6: Commit**

```bash
git add game.gd
git commit -m "feat: wire enemy AI dispatcher in _step_simulation

Replaces _step_enemy_firing with archetype-based real-time steering.
Each enemy now uses its archetype script for steer/fire/evade every frame.
Execution order: cooldown tick -> AI dispatcher -> physics integration."
```

---

## Completion Checklist

Before declaring done:
- [ ] Zero parse errors in Godot Output panel
- [ ] Zero runtime errors during a full play session
- [ ] Aggressor charges directly and fires close-range
- [ ] Orbiter circles at medium distance and fires continuously
- [ ] Flanker tries to get behind the player before firing
- [ ] All three dodge player missiles (Aggressor does not)
- [ ] Game still ends on victory/defeat as before
- [ ] Restart button resets all three archetypes correctly (hit restart after a game)
