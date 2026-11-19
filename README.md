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
| Intake, both sides (hold) | Left trigger | Shift |
| Shoot (hold) | Right trigger | Space |
| Spit pollen back out (hold) | Right bumper | B |
| Slow mode (hold) | Left bumper | Ctrl |
| Turret auto-aim on / off | Right-stick click | T |
| Turret / hood by hand (switches auto-aim off) | D-pad | Z / X and ↑ / ↓ |
| Front lever / back lever (toggle) | A / B | 1 / 2 |
| Player-view ↔ robot-centric driving | Y | F |
| Start a 2:00 driver-controlled match | Start | Enter |
| Start a full match (30 s auto → transition → 2:00) | – | M |
| Reset robot, field and clock | Back | R |
| Run a Java OpMode | – | J |
| Next camera | – | C |
| Show the collision box | – | V |
| Reload `robot_config.json` | – | F5 |

Driving is from the player's point of view by default: W (or stick forward) always moves the robot
away from you on the screen, whichever way the robot faces, and it follows the camera you are
using. Press F (or Y) for robot-centric, where W drives toward the robot's own front.

The flywheel spins all the time. Intake pulls pollen in with a gate shut at the neck; shoot opens
the gate and feeds them to the flywheel. (The gate is an assumption about the real robot: see
`shooter._gate_note` in `robot_config.json`.)

With no match running you are in free practice (no clock).

## Running your real Java code
You need a **JDK 11 or newer** installed (https://adoptium.net). Then, in the running sim:

1. Press **J**. The sim lists every `@TeleOp` / `@Autonomous` OpMode it finds in the TeamCode folder.
2. Press its number. The code is compiled and the OpMode starts in INIT (top right of the screen).
   Compile errors appear there too.
3. Press **Enter** (or Start) to run it, like the play button on the Driver Station. An autonomous
   gets the 30 s clock, a TeleOp the 2:00 clock.
4. Press **R** (or Back) to stop it and get the built-in controls back.

By default the TeamCode folder is `java/teamcode` in this project, which has two samples
(`BiobuzzTeleOp`, `DriveSquareAuto`). To use your real code, set `java.teamcode_dir` in
`robot_config.json` to your `TeamCode/src/main/java` folder. Nothing in your code changes: the sim
provides stand-ins with the same names as the FTC SDK classes (`java/sdk`).

**What the OpMode sees**
- Motors (`DcMotor` / `DcMotorEx`): `frontLeft`, `frontRight`, `backLeft`, `backRight`, `intakeA`,
  `intakeB`, `shooterLeft`, `shooterRight`, and the odometry pods as encoders `odoX`, `odoY`.
  Directions, run modes, `RUN_TO_POSITION`, encoders and `getVelocity()` work.
- Servos: `turretServo` (0..1 = one full turn, 0.5 = centre), `hoodServo`, `gateServo`
  (above 0.5 = open), `leverLeft` (front lever), `leverRight` (back lever).
- `IMU` yaw, `gamepad1` / `gamepad2`, `telemetry`, `ElapsedTime`.
- The main camera as a USB webcam: `hardwareMap.get(WebcamName.class, "Webcam 1")`, used through
  the FTC `VisionPortal` with an `AprilTagProcessor`. `getDetections()` gives each tag in view with
  its `id` and `ftcPose` (`range`, `bearing`, `elevation`, `x`, `y`, `z`) and the robot's field
  position in `robotPose`. See the camera section below.
- The left drive motors are "mounted mirrored" (`drivetrain.motor_inverted`), so code needs the
  usual `setDirection(REVERSE)` on the left side, as on a real robot.

Without a gamepad, the keyboard acts as gamepad1: WASD = left stick, Q/E = right stick X,
Shift = left trigger, Space = right trigger, Ctrl = left bumper, B = right bumper, arrows = D-pad,
1 2 3 4 = A B X Y.

**Not there yet:** the goBILDA Pinpoint driver, Road Runner / Pedro Pathing, FTCLib.
A file that uses something the sim does not have is listed as "EXCLUDED" with the reason and left
out; the rest of your code still runs.

From a terminal, the same thing without the menu (the sim must be running):
```bash
cd java
java RunSim.java --list
java RunSim.java "Biobuzz TeleOp"
```

## Camera and AprilTags
Each hive has an AprilTag under each of its two cells. The main camera (an Arducam) sits on the
shooter and looks where it shoots, tilted up 45 degrees. The sim does not process pictures: it
works out from the robot and turret position which tags are inside the camera's field of view,
within range and facing it, and reports what the FTC `AprilTagProcessor` would. The HUD line
"Camera sees" shows the tags in view right now.

The sample `BiobuzzTeleOp` uses it: right-stick click (T on the keyboard) makes the turret search
for our hive's tag and stay centred on it, using the tag's `bearing`.

Differences from the real thing: tag `yaw` / `pitch` / `roll` are always 0, lens calibration
(`setLensIntrinsics`) is accepted but not needed, and tags are never hidden behind the frame or the
hive. The second camera on the chassis and the two Huskylens are not simulated.

Placeholders in `robot_config.json`: the tag IDs (`field.april_tags`, currently 1 to 4), the
camera's field of view (82 x 56.2 degrees), range, and tag size. `angle_noise_deg` and
`pose_noise_in` add jitter if you want the code tested against imperfect readings.

## Changing robot numbers
Everything lives in **`robot_config.json`**: dimensions, wheel size, motor RPM, track width,
acceleration limits, match times. Edit it, save, press F5 in the running sim. Placeholder
values are listed at the top of that file.

## The robot model (CAD)
The Onshape export lives in `cad/Robot.zip` (the `.glb` inside is about 150 MB, over GitHub's
100 MB file limit, and far too heavy to animate directly). Unzip it to `cad/Robot.glb` before
running the tool; that file is ignored by git.
`tools/process_cad.mjs` turns it into four light pieces in `models/` (chassis, turret, front
lever, back lever; about 12 MB together), each with its origin on its pivot, and writes the
sizes and pivot positions it measured to `models/measurements.json`.

**When the CAD changes:** export the top-level assembly from Onshape as glTF (`.glb`), save it as
`cad/Robot.glb` (and zip it to `cad/Robot.zip` to commit it), then:
```bash
cd tools
npm install
npm run cad
```
Copy any changed numbers from `models/measurements.json` into `robot_config.json`. Besides sizes and
pivots it reports how far the levers are folded out in the export, which way the shooter points,
and the shot angle for the hood position the CAD was exported in. The tool finds
things by part name (`Mecanum Wheel`, `Spur gear (70 teeth)`, the `Patita` / `Torreta` / `Chasis`
groups), so keep those names in Onshape.

The turret turns a full 360° with no end stops (`turret.continuous`; set it to `false` to get the
±32° that a 300° servo gives through the 15:70 gears). With auto-aim on, it keeps the shooter
pointed at the AprilTag under the raised cell of your alliance's hive, and it also sets the hood
angle and trims the flywheel speed so the shot drops into that cell's mouth (and holds the feeders
until the flywheel is at that speed). The HUD says when no shot is possible from where you are:
too close, too far, or on the wrong side of the hive. A green dotted arc shows
where a shot would go with the current flywheel speed and hood angle. The hood part itself is not
animated; the arc is how you see it move.
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

The hives and their A-frame are the real AndyMark models (`cad/field/red_hive.glb`,
`blue_hive.glb`, `hive_frame.glb`, slimmed by `tools/process_field.mjs` with `npm run field`).
Each hive is a seesaw on top of the frame, 43 in above the floor: two tunnel-shaped cells on a
centre pivot, each open at its outer end. Pollen and the robot collide with the real shapes, and
the robot can drive under the hives between the frame legs.

**Hive rule:** when the raised cell holds 8 pollen the seesaw tips. The pollen inside at that
moment are scored for that alliance; they then roll out of the lowered cell and the other cell
becomes the raised one. Pollen that left the cell before the tip do not count. The HUD shows the
balls in each cell and the score.

**Flowers:** a deployed lever held against a flower works as a wedge and the flower drops its
pollen to the floor, one at a time. The flowers are still plain cylinders.

Still **guesses** (in `robot_config.json` under `field`): the hive's tilt angle and tip time, the
flower height, and how close the lever must be. Nectar is not modelled.

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

## Self-tests
```bash
godot --headless -s tests/test_drive.gd
godot --headless -s tests/test_java.gd
```
The second one compiles and runs the sample Java OpModes against the sim (needs a JDK).

## Roadmap
1. ✅ Driver practice MVP
2. ✅ Real robot CAD model (turret + lever pivots)
3. ✅ Pollen, intakes, shooter, turret/lever controls, BIOBUZZ field layout (heights and hive/flower behaviour still guesses)
4. ✅ Java sim SDK + bridge: real OpModes compile and drive the sim (plain TCP with JSON lines rather than WebSocket)
5. Odometry + IMU, sample autonomous (IMU, odometry pod encoders and a sample autonomous are in; Pinpoint, Road Runner and Pedro Pathing are not)
6. ✅ Camera sim: AprilTags through VisionPortal + AprilTagProcessor (the Limelight was dropped; it is not allowed)
