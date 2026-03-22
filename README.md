We're creating a "turn-based" (plan → simulate → plan) top-down space game where the player controls a spaceship by setting its movement vector. The game is primarily mouse-controlled.

# MVP

## MVP goal
Deliver a playable loop as quickly as possible:
- Plan a single movement vector and optionally fire.
- Simulate a short slice of time.
- Repeat until either the player or all enemies are destroyed.

## MVP loop
- The game starts **paused** (planning phase).
- The player may:
  - Adjust **one** movement vector (for the upcoming simulation slice).
  - Fire **one** missile (optional).
- Pressing **Space** simulates the world for **N seconds**, then returns to paused planning.
  - **N defaults to 2 seconds** and must be **easy to tweak** (a single obvious value/setting).

## MVP movement vector UX
- The movement vector is **always visible**, even before the player edits it.
  - By default it should represent "what happens if the player gives no new input" (i.e., continue on the current trajectory).
- The player edits the vector in the paused state.
- The editable range is constrained by ship attributes and by what the ship can plausibly do during the upcoming **N-second** simulation slice.

## MVP physics & collisions (intentionally simple)
- Use simple physics for now (scope limiter).
- All game objects use **simple round/circular colliders**.
- **All collisions are 1-hit kills** for MVP.
- **Draw an outline of colliders** in-game for MVP (debug-visualization so collisions are legible).

## MVP weapons
- Ships fire **straight ahead** (no aiming separate from ship facing direction).
- Missiles:
  - Travel quickly in a straight line.
  - **Die on first hit**.

## MVP enemy behavior
- Enemies move **straight** (no advanced planning/avoidance).

## MVP camera & bounds
- Camera is **locked to/follows the player**.
- Objects can leave the screen/scene; once off-screen they are considered **gone** (culled/removed).

## MVP win/loss flow
- **Objective**: destroy all enemy ships.
- **Victory**: 3 seconds after the objective is met, show a victory message and a **Restart** button.
- **Defeat**: 3 seconds after the player ship is destroyed, show a defeat message and a **Restart** button.
- Restart is a simple, deterministic reset (reload the same board/setup).

---

## Scene
A scene is a "piece of space": an area larger than the viewport, on which Game Objects are placed.

## Game objects
Primary game objects are the player ship, enemy ships, missiles, and environmental doodads (e.g. asteroids).

Common attributes (not all required for MVP):
- Velocity / acceleration
- Turn radius
- Mass
- HP (when reduced to 0, the object is destroyed)

### Player ship
A simple spaceship controlled by the player. Typically starts facing "up."

### Enemy ships
Other spaceships controlled by AI (MVP: straight-line movement).

### Objects / doodads
Asteroids, black holes, and other neutral hazards (optional for MVP).

### Missiles
Projectiles fired by ships. Travel in a straight line and collide with objects.
