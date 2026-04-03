# Design: Newtonian Physics, Scrap, Tractor Beam & New Weapons

**Date:** 2026-04-03
**Status:** Approved

---

## Overview

This spec covers four tightly related areas:

1. **Newtonian physics refactor** — replace kinematic velocity-setting with force-based simulation
2. **Scrap resource** — collectible mass (tons) floating in space, spawned from enemy explosions
3. **Tractor beam** — toggle to pull scrap aboard; spring reel-in, pendulum when over-capacity
4. **New weapons** — homing missile and proximity mine, each with their own ammo

These features are layered: the physics refactor is the foundation everything else builds on.

---

## Section 1: Physics Model

### Core Loop

Every body gains a `mass` (tonnes) property. The simulation loop switches from kinematic to force-based:

```
each sim tick:
  1. accumulate forces into each body's force_accumulator (Vector2)
  2. vel += (force_accumulator / mass) * delta
  3. pos += vel * delta
  4. clear force_accumulator
```

### Forces

| Force | Description |
|---|---|
| **Thrust** | Player and enemies emit thrust force in their chosen direction, clamped to `MAX_THRUST`. Replaces direct velocity assignment. |
| **Gravity** | Bodies above a mass threshold attract each other: `F = G * m1 * m2 / r²`. Applied symmetrically (both bodies feel it). |
| **Explosion impulse** | Existing blast force becomes a proper impulse applied to the accumulator, now mass-weighted (lighter bodies get thrown harder). |
| **Tractor beam** | Spring force or rigid constraint — see Section 3. |
| **Collision** | Ramming becomes a momentum-conserving impulse exchange. |

### Gravity Threshold

Only bodies above a minimum mass threshold **emit** gravity. Bodies below the threshold still **receive** gravity but don't emit it (negligible real-world effect, avoids O(n²) cost from many small pieces).

- **Emit gravity:** player ship, enemy ships, player cargo when absorbed total > 2 t
- **Receive only:** individual scrap pieces (before absorption), missiles, mines, debris

### Body Masses

| Body | Mass |
|---|---|
| Player ship (base) | 10 t |
| Enemy ship | 8 t |
| Scrap piece | 1–3 t (random per piece) |
| Absorbed cargo | adds directly to player mass |
| Missile / mine | negligible |

### Physics Module

A dedicated `physics_sim.gd` owns force accumulation and Newtonian integration. `game.gd` calls into it each tick, passing the list of bodies. This keeps the force math isolated from game rules logic.

---

## Section 2: Planning Interaction

### Thrust Vector Planning

The existing arc/wedge planning UI is replaced with a thrust vector model:

- **Mouse position** relative to the player ship defines the thrust vector: direction + magnitude
- Thrust magnitude is clamped to `MAX_THRUST` (engine limit)
- Moving the mouse updates the preview in real time; left click commits and starts simulation (unchanged from current)

```gdscript
thrust_vec = (mouse_world_pos - player_pos).clamped(MAX_THRUST)
```

### Visual Feedback During Planning

| Element | Description |
|---|---|
| **Thrust arrow** | Drawn from ship center toward mouse. Fades/dims when mouse exceeds `MAX_THRUST` range (showing clamp). |
| **Dotted predicted path** | ~20-step integration of `current_vel + (thrust / mass) * delta` over `SIM_DURATION`. Ends with a ghost ship facing the predicted velocity direction at endpoint. |
| **Zero thrust** | Mouse on ship = coast. Dotted path shows a straight drift line. |

### "Dumb" Preview

The preview intentionally does **not** account for: gravity from other bodies, incoming fire, tractor beam pull, or explosion blasts. It is an honest planning tool, not a guarantee. Real chaos during simulation will often invalidate it — that's by design.

### Turn Radius Is Emergent

No explicit turn rate limit is needed. Turning in space IS thrusting perpendicular to current velocity. Turn radius falls out naturally from physics:

```
turn_radius ≈ (mass × speed²) / thrust_force
```

- Slow/light ship → tight turns
- Fast ship → wide sweeping turns
- Heavy cargo-laden ship → sluggish, wide turns

---

## Section 3: Scrap + Tractor Beam

### Scrap Pieces

Scrap is a persistent physics body (unlike debris which fades). Each piece has:
- `pos: Vector2`
- `vel: Vector2`
- `mass: float` (1–3 t, randomised at spawn)
- Receives gravity, affected by explosions

**Spawning:**
- 2–3 random pieces placed at game start within the play area
- Enemy ship explosions scatter 1–3 scrap pieces from the blast site, inheriting some explosion velocity

**Rendering:** Irregular polygon shape, grey/metallic color. Persistent — does not fade.

### Tractor Beam

The tractor beam is a toggle (not a weapon). It has its own dedicated UI button, separate from the weapon slots. It persists across turns until manually toggled off.

#### Three Phases

**1. Searching** (beam ON, no target)
Auto-locks onto the nearest scrap piece within ~250 units (`TRACTOR_RANGE`). Beam drawn as a dim line sweeping toward it. Tether max length: ~200 units (`TETHER_LENGTH`).

**2. Reel-in** (target locked, scrap fits in remaining cargo capacity)
Spring force applied each sim tick:
- Scrap accelerates toward player
- Player receives equal and opposite force (tugged toward scrap), mass-weighted
- Player is a "sitting duck" — fighting the tug each turn
- When scrap crosses docking distance AND `scrap.mass ≤ remaining_cargo_capacity`: absorbed
  - `player.mass += scrap.mass`
  - `cargo_aboard += scrap.mass`
  - Beam re-searches for next target

**3. Over-capacity** (beam turns red)
`scrap.mass` would exceed remaining cargo space. Tether locks to `TETHER_LENGTH` as a rigid constraint:
- Scrap becomes a pendulum dangling at arm's length
- Player turns drag it; scrap swings back and fights the turn
- Heavy scrap creates significant steering resistance
- Persists until end of round — tethered scrap counts toward end-of-round score

**Releasing the beam:** Toggling beam OFF drops any tethered scrap (it drifts free). Does NOT eject absorbed cargo.

### Cargo Capacity

- Starting capacity: **4 t**
- Absorbed scrap adds permanently to player mass, reducing remaining capacity
- HUD shows cargo bar and `X / 4 t` display, clustered with the ship mass readout

---

## Section 4: New Weapons

### Homing Missile

- **Ammo:** 5 (own pool, separate from basic missile)
- **Color:** Lime `#69ff7d`
- **Shape:** Thin needle triangle + delta-wing outline triangle over rear half
- Fires forward like a basic missile
- Each sim tick: applies a small angular correction toward the nearest enemy (light homing — not a hard lock, can be outrun or outmanoeuvred)
- Same speed and damage as basic missile

### Mine

- **Ammo:** 3 (own pool)
- **Color:** Amber `#ffaa33`
- **Shape:** Small circle (r≈5) with 8 spike lines at cardinal + diagonal directions, dot at each spike tip — classic naval contact mine aesthetic
- Spawned at player's current position, inheriting player's velocity at drop time (drifts naturally with momentum)
- No self-propulsion after drop — pure physics body (affected by gravity and blasts)

**Arming states:**

| State | Duration | Proximity trigger | Weapon/explosion hit |
|---|---|---|---|
| **Arming** | 0–1 s | Disabled | Detonates immediately |
| **Armed** | 1 s+ | Active — any massive body entering trigger radius starts 0.2 s countdown | Detonates immediately |
| **Triggered** | 0.2 s | — | Detonates immediately |

- **Player included** in proximity trigger — fly back through your own armed mine and it detonates
- Proximity trigger radius: ~40 units (`MINE_TRIGGER_RADIUS`)
- The 0.2 s countdown is visually signalled (flash/pulse on mine shape)
- Blast radius and damage same as a regular missile explosion

---

## Section 5: UI Layout

### HUD Structure

| Position | Element |
|---|---|
| Top-left | HP pips |
| Top-center | Tractor beam toggle button |
| Top-right | Ship mass + cargo bar + `X / 4 t` label (clustered) |
| Bottom-center | Weapon slots 1 / 2 / 3 |

### Weapon Slots

Each slot shows: weapon name, ammo dots, cooldown strip. Each weapon has its own color carried through to the in-game projectile:

| Slot | Weapon | Color |
|---|---|---|
| [1] | Missile | Red `#ff4444` |
| [2] | Homing | Lime `#69ff7d` |
| [3] | Mine | Amber `#ffaa33` |

Active slot is highlighted; inactive slots are dimmed. Tractor beam toggle uses Gold `#f5c542` (same family as cargo display).

### Player Ship Color

Player ship changes from cyan to **white** `#ffffff`. This clearly distinguishes it from all other entities and weapon colors.

---

## Color Palette Summary

| Entity | Color |
|---|---|
| Player ship | White `#ffffff` |
| Enemy ships | Per-archetype: Red / Orange / Purple (unchanged) |
| Basic missile | Red `#ff4444` |
| Homing missile | Lime `#69ff7d` |
| Mine | Amber `#ffaa33` |
| Tractor beam / cargo UI | Gold `#f5c542` |
| Scrap pieces | Cool grey `#a0a8b0` |

---

## Implementation Order

0. **Update game documentation** — update README and any existing docs to reflect the game's current state and the new physics model before touching code
1. **`physics_sim.gd`** — force accumulator, Newtonian integration, gravity
2. **Refactor `game.gd`** — replace kinematic movement with thrust forces for player and enemies; update planning UI to thrust vector + dotted path preview
3. **Scrap system** — scrap array, spawning at start + from explosions, renderer
4. **Tractor beam** — spring reel-in, cargo absorption, over-capacity pendulum constraint, UI toggle
5. **Homing missile** — per-tick steering correction, lime color, new ammo pool
6. **Mine** — drop mechanics, arming states, proximity trigger, amber color, new ammo pool
7. **HUD update** — weapon slots with per-color styling, tractor toggle, mass+cargo cluster, player ship → white
