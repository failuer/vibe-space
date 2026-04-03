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
