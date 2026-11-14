# BIOBUZZ FTC Simulator (Godot 4)

Driver practice and (later) real-OpMode testing for our FTC robot.

![Phase 2](docs/phase2.png)

## Run it
1. Install **Godot 4.5 or newer** (standard version, not .NET): https://godotengine.org/download
2. Open Godot → **Import** → pick this folder's `project.godot` → **Run** (F5 key in the editor, or the ▶ button).
3. Plug in a USB gamepad (Xbox / PlayStation / Logitech all work). No gamepad? Use the keyboard.

| Action | Gamepad | Keyboard |
|---|---|---|
| Drive / strafe | Left stick | W A S D |
| Turn | Right stick X | Q / E |
| Slow mode (hold) | Left bumper | Shift |
| Robot-centric ↔ field-centric | Y | F |
| Reset field-centric "forward" to where the robot faces now | X | H |
| Start a 2:00 driver-controlled match | Start | Enter |
| Start a full match (30 s auto → transition → 2:00) | – | M |
| Front intake (side A) / back intake (hold) | Right trigger / left trigger | I / K |
| Reverse the intakes (hold with the above) | Right-stick click | Ctrl |
| Shooter flywheel on / off | Right bumper | G |
| Hood up / down | D-pad ↑ / ↓ | ↑ / ↓ |
| Turret left / right | D-pad ← / → | Z / X |
| Front lever / back lever (toggle) | A / B | 1 / 2 |
| Show the collision box | – | V |
| Reset robot + clock | Back | R |
| Next camera (driver station / top-down / chase) | Left-stick click | C |
| Reload `robot_config.json` | – | F5 |

With no match running you are in free practice (no clock).

## Changing robot numbers
Everything lives in **`robot_config.json`**: dimensions, wheel size, motor RPM, track width,
acceleration limits, match times. Edit it, save, press F5 in the running sim. Placeholder
values are listed at the top of that file.

## The robot model (CAD)
The Onshape export lives in `cad/Robot.glb` (93 MB, far too heavy to animate directly).
`tools/process_cad.mjs` turns it into four light pieces in `models/` (chassis, turret, front
lever, back lever; about 12 MB together), each with its origin on its pivot, and writes the
sizes and pivot positions it measured to `models/measurements.json`.

**When the CAD changes:** export the top-level assembly from Onshape as glTF (`.glb`), replace
`cad/Robot.glb`, then:
```bash
cd tools
npm install
npm run cad
```
Copy any changed numbers from `models/measurements.json` into `robot_config.json`. The tool finds
things by part name (`Mecanum Wheel`, `Spur gear (70 teeth)`, the `Patita` / `Torreta` / `Chasis`
groups), so keep those names in Onshape.

The turret follows a servo position (0..1) through the 15:70 gears, so a 300° servo gives ±32°.
Levers go 0° (stowed) to 90° (deployed). Both move at a limited speed set in the config.
Known limit: deployed levers do not collide with anything yet; only the chassis box does.

## Pollen, intakes and shooter
- **Pollen** are real physics balls (3 in). The robot pushes them around; they never block it.
- **Intakes:** a ball touching an intake mouth while that intake motor runs is swallowed into
  that side's feeder. The robot holds at most `intakes.total_capacity` balls.
- **Feeders and shooter:** each intake motor also runs its feeder, carrying balls up to the shared
  neck. A ball at the neck waits there until the flywheel is spinning *and* its intake motor
  runs; then it is launched out of the turret's Limelight side at the hood angle. Each shot
  slows the flywheel a little.

## The field
The floor plan is the real BIOBUZZ one: it is read from `data/field_layout.json` and
`data/game_elements.json`, which come from the BEE simulator (see `data/README.md`). That gives
the loading zones, gardens, the four flowers (4 pollen each), the hive frame, the red and blue hive
cells, and where every pollen starts. The robot starts with 4 pollen loaded.

Those files do not give heights or how things move, so these are **guesses** (in
`robot_config.json` under `field`): flower and cell heights, a deployed lever held against a flower
making it drop its pollen, and hive cells being plain fixed bins (the real hive tips; nectar is not
modelled). The HUD shows how many balls sit in each cell; there is no scoring yet.

The driver stands behind the red wall (left) by default; set `driver.alliance` to `blue` to switch.

All speeds, capacities and angles here are placeholders in `robot_config.json`.

## How the driving works
`scripts/robot.gd` takes four wheel powers (-1..1, like `motor.setPower()`), converts them to a
chassis velocity with the mecanum equations, applies acceleration limits, and moves a collision
box. Top speed = motor RPM × wheel circumference × `loaded_speed_fraction`. It also tracks
wheel encoder ticks for the Java bridge in Phase 4. `scripts/builtin_teleop.gd` is the built-in
TeleOp that turns sticks into those wheel powers.

Coordinates shown on the HUD are FTC-style: inches, origin at field centre, heading
counter-clockwise. Red wall is −x, blue wall is +x, audience is −y.

## Self-test
```bash
godot --headless -s tests/test_drive.gd
```

## Roadmap
1. ✅ Driver practice MVP
2. ✅ Real robot CAD model (turret + lever pivots)
3. ✅ Pollen, intakes, shooter, turret/lever controls, BIOBUZZ field layout (heights and hive/flower behaviour still guesses)
4. Java sim SDK + WebSocket bridge (run real OpModes)
5. Odometry + IMU, sample autonomous
6. Limelight sim
