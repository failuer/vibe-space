# Real-Time Firing + Code Restructure — Design Spec
**Date:** 2026-03-22
**Beads issues:** vibe-space-pqn (firing), vibe-space-a8l (refactor)
**Status:** Approved for implementation

---

## Overview

Add real-time weapon firing for both the player and enemy ships during the simulation phase, alongside a code restructure that splits the monolithic `new_script.gd` into separate logic and rendering files.

---

## 1. Code Structure (vibe-space-a8l)

Rename and split `new_script.gd` into two files, and rename the scene for clarity:

| Old | New | Responsibility |
|-----|-----|----------------|
| `new_script.gd` | `game.gd` | All game logic: state, phases, input, simulation, AI |
| _(new)_ | `game_renderer.gd` | All `_draw*` functions; reads game state, never writes it |
| `node_2d.tscn` | `game_world.tscn` | Scene file |

`game_renderer.gd` attaches to a child `Node2D` of the root. It acquires a reference to the parent via `get_parent()` on `_ready`, typed as the `Game` class. It reads the parent's state variables directly each frame — no `@export` wiring needed. This boundary is enforced by convention: the renderer calls no mutating methods on the parent.

---

## 2. Weapon / Ammo Data Model

Each combatant (player and each enemy) tracks two values:

- `max_missiles: int` — the ship's capacity (player starts at 10; enemies TBD, suggest 6)
- `missiles_remaining: int` — how many shots are left this round
- `fire_cooldown: float` — seconds remaining before next shot is allowed (counts down to 0)

**Constants (player):**
- `PLAYER_MAX_MISSILES := 10`
- `PLAYER_FIRE_COOLDOWN := 4.0` seconds

**Constants (enemy):**
- `ENEMY_MAX_MISSILES := 6`
- `ENEMY_FIRE_COOLDOWN := 3.5` seconds

Ammo is fixed for the round — no reload mechanic at this stage. This is designed to accommodate future per-ship inventory from the management phase.

Enemy ammo and cooldown values are stored per-enemy in the existing dictionary: `{ pos, vel, alive, missiles_remaining, fire_cooldown }`.

---

## 3. Player Firing Mechanic

### Input
A dedicated **fire button** in the `CanvasLayer` replaces the old left-click-to-toggle-planned-fire mechanism.

- **Planning phase:** pressing fire queues a shot to be spawned at simulation start (same result as before), consumes 1 missile and starts the cooldown immediately. The cooldown carries over into the simulation phase — it does not reset at sim start.
- **Simulation phase:** pressing fire spawns a missile immediately in the ship's current facing direction, consumes 1 missile and starts cooldown.
- Button is disabled (non-interactive) while `fire_cooldown > 0` or `missiles_remaining == 0`.

### Fire Button UI (CanvasLayer, consistent with existing RestartButton)

**Shape:** Wide pill (`180×44px`, `border-radius: 22px`), cyan border matching the player ship colour. Positioned in the bottom-centre of the screen via `CanvasLayer`, above the existing `RestartButton` anchor point. Anchored to `PRESET_BOTTOM_CENTER` with a small upward offset.

**Label:** Switches in-place:
- `FIRE` — when ready
- `RELOADING...` — while cooldown is active
- `NO AMMO` — when `missiles_remaining == 0` (button fades, border at 25% opacity)

**Cooldown fill:** A `ColorRect` inside the pill sweeps left-to-right over `PLAYER_FIRE_COOLDOWN` seconds, representing time elapsed since last shot. Fills from 0% to 100% as cooldown expires.

**Ammo indicator:** A row of missile glyphs below the pill — one per `max_missiles`. Each glyph is a circle outline in missile yellow (`#ffff66`, `12px` diameter, `1.5px` stroke), matching the in-game missile render exactly:
- `missiles_remaining` dots: fully opaque
- Spent dots (`max_missiles - missiles_remaining`): ~20% opacity

---

## 4. Enemy Firing AI

Enemies fire autonomously during simulation only (they do not pre-plan shots).

**Firing condition (per enemy, checked each frame):**
1. `fire_cooldown <= 0`
2. `missiles_remaining > 0`
3. Player is alive
4. The angle between the enemy's current velocity direction and the vector to the player is within `45°` (a "reasonable shot" — enemy is roughly facing the player)
5. Player is within `SCENE_RADIUS` (already culled otherwise)

When all conditions are met, the enemy fires one missile aimed at the player's **current position** (no prediction at this stage) and resets its `fire_cooldown`.

Enemies do not fire during the planning phase.

---

## 5. Missile Spawning (shared logic)

No change to missile data structure: `{ pos, vel, from_player }`. Enemy missiles spawned by the AI use `from_player: false`, same as the existing sim-start shots.

The existing collision and culling logic handles all missiles regardless of when they were spawned.

---

## 6. What Is Removed

- `planned_fire: bool` variable and all references — replaced by the fire button system.
- The left-click mouse input during planning that toggled `planned_fire`.

---

## 7. Out of Scope (future issues)

- Ammo reload / recharge (vibe-space-zik)
- Laser / alternative weapon types (vibe-space-is2)
- Weapon switching UI
- Enemy pre-planned shots during planning phase
- Projectile prediction in enemy AI
