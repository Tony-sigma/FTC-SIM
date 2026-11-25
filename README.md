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
| Bring one of your waiting nectar into the loading zone | – | N |
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

## Playing it as a game (no Godot needed)
The sim can be built into a normal program for Windows, Mac and Linux. A build is a folder with the
game, `robot_config.json` and the `java` folder; keep them together. Editing `robot_config.json`
and pressing F5 still works, and so does J for Java OpModes.

To make the builds yourself: open the project in Godot, **Project → Export**, install the export
templates when it asks, pick Windows or macOS and press **Export Project**. Then copy
`robot_config.json` and the `java` folder next to the exported game. From a terminal:
```bash
godot --headless --export-release "Windows" export/windows/BiobuzzSim.exe
godot --headless --export-release "macOS" export/macos/BiobuzzSim.zip
```
A build is a snapshot: after `git pull` you need to export again to get the changes.

Without building anything, this starts the sim directly, skipping the Godot editor:
```bash
godot --path .
```

Start options, after `--`: `--opmode="Biobuzz TeleOp"` launches that Java OpMode right away and
`--start` presses start for it.

## Running your real Java code
You need a **JDK 11 or newer** installed (https://adoptium.net). Then, in the running sim:

1. Press **J**. The sim lists every `@TeleOp` / `@Autonomous` OpMode it finds in the TeamCode folder.
2. Press its number. The code is compiled and the OpMode starts in INIT (top right of the screen).
   Compile errors appear there too.
3. Press **Enter** (or Start) to run it, like the play button on the Driver Station. An autonomous
   gets the 30 s clock, a TeleOp the 2:00 clock.
4. Press **R** (or Back) to stop it and get the built-in controls back.

By default the TeamCode folder is `java/teamcode` in this project, which has two samples
(`BiobuzzTeleOp`, `DriveSquareAuto`) and nine test OpModes, one per mechanism (see below). To use your real code, set `java.teamcode_dir` in
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
Each hive cell has a cluster of four AprilTags (36h11) on its underside: RED SCORING 30-33,
RED AUDIENCE 34-37, BLUE AUDIENCE 38-41, BLUE SCORING 42-45 (from the official AprilTag art).
As in FTC SDK 12.0, `getDetections()` returns one `AprilTagClusterDetection` per cluster in view.
Its pose points at the centre of that cell's opening, `metadata.name` is the cluster's name,
`percentClusterFound` says how many of the four tags were read, and `ftcPose.roll` tells you which
way up it is: between -90 and 90 means the raised cell you can score in.

The main camera (an Arducam) sits on the shooter and looks where it shoots, tilted up 45 degrees.
The sim does not process pictures: it works out from the robot and turret position which tags are
inside the camera's field of view, within range and facing it. The HUD line "Camera sees" shows the
clusters in view right now.

The sample `BiobuzzTeleOp` uses it the way the FTC tech tip describes: right-stick click (T on the
keyboard) makes the turret search for a cluster whose name starts with our colour and whose roll
is the right way up, then keeps it centred using `bearing`.

Differences from the real thing: `yaw` and `pitch` are always 0, lens calibration
(`setLensIntrinsics`) is accepted but not needed, and tags are never hidden behind the frame or the
hive. The second camera on the chassis and the two Huskylens are not simulated.

Placeholders in `robot_config.json`: the camera's field of view (82 x 56.2 degrees) and range.
`angle_noise_deg` and `pose_noise_in` add jitter if you want the code tested against imperfect
readings.

## Test OpModes for the real robot
In `java/teamcode/org/firstinspires/ftc/teamcode/`, each with its instructions at the top of the
file. They are ordinary FTC code: try them in the sim (press J), then copy them to the robot.
A device that is missing from the robot configuration is reported on the screen, not a crash.

| OpMode | File | What it is for |
|---|---|---|
| Test: Drive Motors | `TestDriveMotors.java` | One wheel at a time (X Y A B), to check ports, names and directions. Wheels off the ground! |
| Test: Turret | `TestTurret.java` | Only the turret servo: arm it, turn it slowly, read off its safe limits. |
| Test: Hood | `TestHood.java` | Only the hood servo: find its two end positions. The flywheel stays off. |
| Test: Levers | `TestLevers.java` | Only the levers, one at a time: find each one's resting and fully-out positions. |
| Test: Shooter | `TestShooter.java` | Only the flywheel, at a power you step up slowly, showing each motor's rpm. Capped at 0.40. |
| Test: Intake + Feeder | `TestIntakes.java` | Each intake with its feeder (one motor each) on its own trigger, with reverse. |
| Test: Sensors | `TestSensors.java` | IMU heading and the encoders while you move the robot by hand. Nothing is powered. |
| Test: Camera | `TestCamera.java` | Lists the AprilTag clusters in view with range, bearing, and whether the cell can be scored in. |
| Test: Any Servo | `TestServos.java` | A general servo tester for anything else, such as the gate. |

`godot --headless -s tests/test_mechanism_opmodes.gd` runs them all in the sim.

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
where a shot would go with the current flywheel speed and hood angle. The hood, its top wheel and
the flywheel are separate models, so you can see the hood swing and the wheels turn (slowed down).
Levers rest at 100° and swing to 138° to work the flowers (0° = straight up, 90° = flat). Both move
at a limited speed set in the config. Known limit: the levers do not collide with anything yet;
only the chassis box does.

## Pollen, intakes and shooter
- **Pollen** are real physics balls (3 in). The robot pushes them around; they never block it.
- **Intakes:** a ball touching an intake mouth while that intake motor runs is swallowed into
  that side's feeder. The robot holds at most `intakes.total_capacity` balls.
- **Flight:** a shot is slowed by air drag, and because the top wheel's surface runs faster than the
  flywheel's it leaves with topspin, which makes it dip. The green arc and the automatic hood use
  the same model. The spin and lift numbers are placeholders (`pollen._air_note`).
- **Shooting on the move:** a ball keeps the robot's own speed when it leaves, so the auto-aim leads
  the shot: the turret points ahead by (robot speed × flight time) and the hood and flywheel are
  worked out as seen from the moving robot (`driver.lead_moving_shots`). Fire is held while the
  turret is more than 3° from where it should point; the HUD then says TURRET CATCHING UP. That
  happens when the robot passes close to the hive at speed, or turns faster than the turret can
  (`turret.servo_speed_deg_per_s` through the 15:70 gears). `tests/test_moving_shot.gd` prints a
  table of drive speed against shots scored.
- **Feeders and shooter:** each intake motor also runs its feeder, carrying balls up to the shared
  neck. A ball at the neck waits there until the flywheel is spinning *and* its intake motor
  runs; then it goes through the wheels and out of the turret at the hood angle.
- **Shooter physics:** the two pairs of green wheels are 54.3 mm apart, so a pollen is squashed
  16.8 mm and a nectar 37.1 mm on the way through. That takes energy out of everything that spins
  (the two 0.125 kg flywheel weights, the two 4 in wheels and the two 3 in wheels): each ball slows
  the wheels, a nectar about three times as much as a pollen, and the motors then bring the speed
  back. A ball leaves slower when the wheels are still recovering, so a stream of shots only stays
  on target if the code *holds* the flywheel speed (`RUN_USING_ENCODER` / `setVelocity`); with
  plain `setPower` every shot is weaker than the last. A flywheel turning too slowly cannot squeeze
  a nectar through at all: it jams (the HUD says so) until you stop feeding and spin up. The HUD
  shows the last shot's speed and how far the flywheel dipped. How stiff the balls are and how well
  the wheels grip are placeholders: see `pollen._squeeze_note` and `shooter._grip_note`.

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

**Nectar:** the bigger, heavier ball (3.6 in, 26.5 g, red or blue). As in a real match, three
start in each raised hive cell and five more per alliance wait off the field. The humans put one
into their loading zone after every tip of their own hive, and all the rest when a minute is left
(in free practice press **N** to bring one in). The intake, feeders and shooter handle nectar like
pollen, with its own size and weight; the automatic hood aims for whichever ball is next in line.

**Hive rule:** the seesaw tips when the weight in the raised cell reaches 100 g (`field.hive_tip_weight_g`:
8 pollen, or 4 nectar, or a mix). The three nectar that start in the cell already weigh 79.5 g, so
the first tip of a match needs only 2 pollen. Everything inside then rolls out of the lowered cell
and the other cell becomes the raised one.

**Flowers:** the real AndyMark flower (`cad/field/flower.glb`). Pollen stand in a stack inside it. A
deployed lever held under a flower wedges out the bottom pollen, one at a time, and it rolls to the
robot. A ball dropped in through the top ring joins the stack. A nectar is too big to pass the
middle ring, so it stays in the flower and blocks any pollen above it.

**Points** (HUD, as if the match ended now): 20 per hive tip, 2 per ball still in your raised cell,
2 per ball in a flower you own (your nectar is the top-most one in it), 5 for the bottom-most nectar
in each flower, 1 per ball in your garden. LEAVE, PARK and fouls are not counted.

Still **guesses** (in `robot_config.json` under `field`): the weight that tips the hive (the manual
gives none), its tip time, and how close the lever must be to a flower.

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
godot --headless -s tests/test_mechanism_opmodes.gd
godot --headless -s tests/test_nectar.gd
godot --headless -s tests/test_moving_shot.gd
```
The second one compiles and runs the sample Java OpModes against the sim (needs a JDK).

## Roadmap
1. ✅ Driver practice MVP
2. ✅ Real robot CAD model (turret + lever pivots)
3. ✅ Pollen, intakes, shooter, turret/lever controls, BIOBUZZ field layout (heights and hive/flower behaviour still guesses)
4. ✅ Java sim SDK + bridge: real OpModes compile and drive the sim (plain TCP with JSON lines rather than WebSocket)
5. Odometry + IMU, sample autonomous (IMU, odometry pod encoders and a sample autonomous are in; Pinpoint, Road Runner and Pedro Pathing are not)
6. ✅ Camera sim: AprilTags through VisionPortal + AprilTagProcessor (the Limelight was dropped; it is not allowed)
