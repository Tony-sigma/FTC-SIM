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
| Turn | Right stick X | Q / E or ← / → |
| Slow mode (hold) | Left bumper | Shift |
| Robot-centric ↔ field-centric | Y | F |
| Reset field-centric "forward" to where the robot faces now | X | H |
| Start a 2:00 driver-controlled match | Start | Enter |
| Start a full match (30 s auto → transition → 2:00) | – | M |
| Turret left / right | D-pad ← / → | Z / X |
| Front lever / back lever (toggle) | A / B | 1 / 2 |
| Show the collision box | – | V |
| Reset robot + clock | Back | R |
| Next camera (driver station / top-down / chase) | Right bumper | C |
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

## How the driving works
`scripts/robot.gd` takes four wheel powers (-1..1, like `motor.setPower()`), converts them to a
chassis velocity with the mecanum equations, applies acceleration limits, and moves a collision
box. Top speed = motor RPM × wheel circumference × `loaded_speed_fraction`. It also tracks
wheel encoder ticks for the Java bridge in Phase 4. `scripts/builtin_teleop.gd` is the built-in
TeleOp that turns sticks into those wheel powers.

Coordinates shown on the HUD are FTC-style: inches, origin at field centre, heading
counter-clockwise. The driver stands on the −y side, and the robot starts facing +y (90°).

## Self-test
```bash
godot --headless -s tests/test_drive.gd
```

## Roadmap
1. ✅ Driver practice MVP
2. ✅ Real robot CAD model (turret + lever pivots)
3. Pollen, intakes, turret/lever controls
4. Java sim SDK + WebSocket bridge (run real OpModes)
5. Odometry + IMU, sample autonomous
6. Limelight sim
