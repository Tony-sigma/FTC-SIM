package org.firstinspires.ftc.teamcode;

import android.util.Size;
import com.qualcomm.robotcore.eventloop.opmode.OpMode;
import com.qualcomm.robotcore.eventloop.opmode.TeleOp;
import com.qualcomm.robotcore.hardware.DcMotor;
import com.qualcomm.robotcore.hardware.DcMotorEx;
import com.qualcomm.robotcore.hardware.DcMotorSimple;
import com.qualcomm.robotcore.hardware.Servo;
import org.firstinspires.ftc.robotcore.external.hardware.camera.WebcamName;
import org.firstinspires.ftc.vision.VisionPortal;
import org.firstinspires.ftc.vision.apriltag.AprilTagClusterDetection;
import org.firstinspires.ftc.vision.apriltag.AprilTagDetection;
import org.firstinspires.ftc.vision.apriltag.AprilTagProcessor;
import java.util.ArrayList;
import java.util.List;

/**
 * Only the camera and the shooter: turret, hood, flywheel, feeders and gate. The wheels and the levers
 * are not touched, so the robot can stand on blocks. Use it to get the shooter working and to build
 * the shot table.
 *
 * THE FLYWHEEL IS OFF UNTIL YOU PRESS X. Nobody in front of the shooter, safety glasses on.
 *
 *   X                  flywheel ON / OFF
 *   Y / A              flywheel speed for shots by hand: +250 / -250 rpm
 *                      (hold the LEFT BUMPER while pressing for fine steps of 25)
 *   D-pad up / down    hood by hand           (only while auto-aim is off)
 *   D-pad left / right turret by hand         (switches auto-aim off)
 *   Right stick click  AUTO-AIM on / off: the camera keeps the turret on our hive's raised cell and
 *                      sets the hood and the flywheel speed from the shot table
 *   Left trigger       feeders run, gate shut (bring balls up to the neck)
 *   Right trigger      SHOOT (waits until the flywheel and the aim are ready)
 *   Right bumper       feeders backwards (spit out)
 *   Left stick click   NECTAR mode on / off (flywheel a little faster)
 *
 * Building the shot table: auto-aim off, put the robot at a distance from the hive, read "distance" on
 * the screen, find the hood and speed that drop the ball in, and copy the "Table row" line into
 * SHOT_TABLE here and in BiobuzzTeleOp. Do that every foot or so, nearest to furthest.
 *
 * Names needed in the robot configuration (anything missing is skipped and listed on the screen):
 *   motors  shooterLeft, shooterRight, intakeA, intakeB
 *   servos  turretServo, hoodServo, gateServo
 *   webcam  "Webcam 1"
 */
@TeleOp(name = "Camera + Shooter", group = "Biobuzz")
public class CameraShooterTeleOp extends OpMode {

    // =====================================================================================================
    //  ROBOT SETTINGS. Check each one with its "Test: ..." OpMode first. Keep them the same as BiobuzzTeleOp.
    // =====================================================================================================

    /** Our alliance: "RED" or "BLUE". The camera only aims at hive cells of this colour. */
    static final String OUR_ALLIANCE = "RED";

    // ---- Intakes / feeders (check with "Test: Intakes": positive must pull balls IN and up) ----
    static final boolean REVERSE_INTAKE_A = false;
    static final boolean REVERSE_INTAKE_B = false;

    // ---- Shooter (check with "Test: Shooter": both motors must turn the flywheel the SAME way) ----
    // Found on the real robot (2026-11): left reversed, right not. With both the same the two motors
    // fight; with them the other way round the flywheel spins backwards and pulls the balls back in.
    static final boolean REVERSE_SHOOTER_LEFT = true;
    static final boolean REVERSE_SHOOTER_RIGHT = false;
    /**
     * How the flywheel speed is held. The two shooter motors turn the same wheels, so the hub must NOT
     * control each one's speed by itself: the two controllers pull against each other (seen on the real
     * robot: one motor at 0 and then at 3000 rpm, the battery sagging, a grinding sound). Instead the
     * code measures the speed with ONE encoder and gives BOTH motors the same power.
     *   true  = hold the speed. Needs the encoder cable of the motor chosen in SHOOTER_SPEED_FROM_LEFT.
     *   false = plain power, no encoder needed. A stream of shots then gets weaker and weaker.
     */
    static final boolean SHOOTER_HOLD_SPEED = true;
    /** Whose encoder measures the flywheel: true = shooterLeft, false = shooterRight. Pick the one that reads steadily. */
    static final boolean SHOOTER_SPEED_FROM_LEFT = true;
    static final double SHOOTER_TICKS_PER_REV = 28.0;   // bare goBILDA Yellow Jacket motor
    /** Roughly the speed at full power on the real robot. It only sets the first guess at the power; the encoder corrects the rest. */
    static final double SHOOTER_MAX_RPM = 5000.0;
    /**
     * Speed-hold tuning. Power = (speed wanted / max speed) + KP x (how far short it is, as a share of max
     * speed) + KI x (that shortfall added up over time). Raise KP if it is slow to recover after a ball;
     * lower it if the speed hunts up and down.
     */
    static final double SHOOTER_KP = 5.0, SHOOTER_KI = 2.0;
    /** Flywheel speed for shots by hand when the OpMode starts. Y and A change it. */
    static final double MANUAL_RPM = 1400.0;
    /**
     * The fastest Y will take it: about everything these motors reach on the real robot. Remember the top
     * wheels are geared 2.25 times faster than this number (36:24 gears, then 30:20 pulleys): 5000 here is
     * about 11000 rpm on the small wheels and their printed pulleys. Stay behind the robot at these speeds.
     */
    static final double MANUAL_RPM_LIMIT = 5000.0;
    /** A nectar needs the flywheel about this much faster than a pollen for the same shot. */
    static final double NECTAR_SPEED_FACTOR = 1.04;
    /** Shoot only while the flywheel is within this fraction of the speed the shot needs. */
    static final double SPEED_TOLERANCE = 0.06;

    // ---- Gate servo at the neck (check with "Test: Servos"). No gate on the robot? Leave it out of the configuration. ----
    static final double GATE_CLOSED = 0.0, GATE_OPEN = 1.0;

    // ---- Turret servo (check with "Test: Turret") ----
    /** Servo position that points the shooter straight ahead. */
    static final double TURRET_CENTER = 0.5;
    /** The furthest the servo may go each way before something hits. */
    static final double TURRET_MIN = 0.0, TURRET_MAX = 1.0;
    /** Degrees the TURRET turns when the servo goes from 0 to 1: servo travel x 15 / 70 (300 degree servo = 64.3). */
    static final double TURRET_TRAVEL_DEG = 64.3;
    /** +1 if a bigger servo position turns the turret LEFT (counter-clockwise seen from above), -1 if it turns it right. */
    static final double TURRET_LEFT_SIGN = 1.0;
    /** How fast the turret can really turn. Torque servo about 50 deg/s, Speed servo about 115. */
    static final double TURRET_SPEED_DEG_PER_S = 50.0;
    /** Share of the aiming error corrected on each new camera frame. Lower it if the turret wobbles around the target. */
    static final double AIM_GAIN = 0.35;
    /** Shoot only while the camera says the turret is within this many degrees of the cell. */
    static final double AIM_TOLERANCE_DEG = 3.0;

    // ---- Hood servo (check with "Test: Hood") ----
    /** Servo position with the hood at its FLATTEST shot, and at its STEEPEST shot. */
    static final double HOOD_FLAT = 0.0, HOOD_STEEP = 1.0;

    // ---- Camera on the shooter (check with "Test: Camera") ----
    static final String CAMERA_NAME = "Webcam 1";
    static final int CAMERA_WIDTH = 640, CAMERA_HEIGHT = 480;
    static final boolean CAMERA_MJPEG = true;
    /** Lens calibration made at that picture size. Without it the turret still aims, but the distance is wrong. */
    static final boolean USE_LENS_CALIBRATION = false;
    static final double LENS_FX = 0.0, LENS_FY = 0.0, LENS_CX = 0.0, LENS_CY = 0.0;

    /**
     * THE SHOT TABLE: distance from the camera to the cell's opening (inches), hood (0 = flattest,
     * 1 = steepest), flywheel rpm for a POLLEN. In between two rows the code blends them.
     * These numbers come from the simulator: a STARTING POINT. Replace them with rows you measure.
     */
    static final double[][] SHOT_TABLE = {
        // distance, hood, rpm
        {57.0, 1.00, 1355},
        {60.0, 1.00, 1370},
        {63.0, 1.00, 1393},
        {66.5, 1.00, 1426},
        {70.5, 0.93, 1456},
        {74.0, 0.86, 1490},
        {78.0, 0.79, 1523},
        {82.5, 0.79, 1557},
        {86.5, 0.72, 1591},
        {91.0, 0.72, 1627},
    };

    // =====================================================================================================

    private DcMotorEx intakeA, intakeB, shooterLeft, shooterRight;
    private Servo turretServo, hoodServo, gateServo;
    private VisionPortal visionPortal;
    private AprilTagProcessor aprilTag;
    private final List<String> missing = new ArrayList<>();
    private double speedSum = 0.0, speedSeenAt = 0.0;
    private boolean speedBlind = false;

    private double turret = TURRET_CENTER, hood = 0.5, manualRpm = MANUAL_RPM;
    private boolean flywheelOn = false, autoAim = false, nectarMode = false;
    private boolean lastX, lastY, lastA, lastRightStick, lastLeftStick;
    private double sweepDirection = 1.0, lastLoopTime = 0.0, flywheelOnSince = 0.0;
    private double dipRpm = 0.0, dipSeenAt = -10.0;
    // What the camera last saw of our raised cell.
    private boolean seesCell = false;
    private double cellBearing = 0.0, cellDistance = 0.0, cellSeenAt = -10.0;
    private String cellName = "";
    private int cellPercent = 0;

    @Override
    public void init() {
        intakeA = motor("intakeA", REVERSE_INTAKE_A);
        intakeB = motor("intakeB", REVERSE_INTAKE_B);
        shooterLeft = motor("shooterLeft", REVERSE_SHOOTER_LEFT);
        shooterRight = motor("shooterRight", REVERSE_SHOOTER_RIGHT);
        for (DcMotorEx m : new DcMotorEx[]{shooterLeft, shooterRight}) {
            if (m == null) continue;
            m.setZeroPowerBehavior(DcMotor.ZeroPowerBehavior.FLOAT);
            m.setMode(DcMotor.RunMode.RUN_WITHOUT_ENCODER);   // the code below holds the speed, not the hub
        }

        turretServo = servo("turretServo");
        hoodServo = servo("hoodServo");
        gateServo = servo("gateServo");

        WebcamName webcam = hardwareMap.tryGet(WebcamName.class, CAMERA_NAME);
        if (webcam == null) {
            missing.add(CAMERA_NAME);
        } else {
            AprilTagProcessor.Builder tags = new AprilTagProcessor.Builder();
            if (USE_LENS_CALIBRATION) tags.setLensIntrinsics(LENS_FX, LENS_FY, LENS_CX, LENS_CY);
            aprilTag = tags.build();
            visionPortal = new VisionPortal.Builder()
                .setCamera(webcam)
                .setCameraResolution(new Size(CAMERA_WIDTH, CAMERA_HEIGHT))
                .setStreamFormat(CAMERA_MJPEG ? VisionPortal.StreamFormat.MJPEG : VisionPortal.StreamFormat.YUY2)
                .addProcessor(aprilTag)
                .build();
        }

        telemetry.addData("Status", "Ready. The flywheel stays OFF until you press X.");
        if (!missing.isEmpty()) telemetry.addData("NOT in this configuration", missing);
    }

    @Override
    public void loop() {
        double now = getRuntime();
        double dt = Math.max(0.001, Math.min(0.1, now - lastLoopTime));
        lastLoopTime = now;

        // ---- camera: find our raised cell ----
        // Each hive cell has a cluster of four AprilTags, reported as one detection that points at the
        // centre of the cell's opening. Ours has a name starting with our colour, and the raised cell
        // (the one we can score in) is the right way up: roll between -90 and 90.
        boolean freshFrame = false;
        if (aprilTag != null) {
            List<AprilTagDetection> fresh = aprilTag.getFreshDetections();   // null until the camera has a new picture
            if (fresh != null) {
                freshFrame = true;
                seesCell = false;
                for (AprilTagDetection d : fresh) {
                    if (seesCell || !(d instanceof AprilTagClusterDetection)) continue;
                    AprilTagClusterDetection cluster = (AprilTagClusterDetection) d;
                    if (cluster.metadata == null || cluster.ftcPose == null) continue;
                    if (!cluster.metadata.name.startsWith(OUR_ALLIANCE) || Math.abs(cluster.ftcPose.roll) >= 90) continue;
                    seesCell = true;
                    cellSeenAt = now;
                    cellName = cluster.metadata.name;
                    cellPercent = cluster.percentClusterFound;
                    cellBearing = cluster.ftcPose.bearing;
                    // Straight-line distance from the camera to the cell's opening.
                    cellDistance = Math.sqrt(cluster.ftcPose.x * cluster.ftcPose.x + cluster.ftcPose.y * cluster.ftcPose.y + cluster.ftcPose.z * cluster.ftcPose.z);
                }
            }
        }
        // A picture older than half a second is no use for aiming.
        boolean cellKnown = seesCell && now - cellSeenAt < 0.5;

        // ---- turret ----
        if (gamepad1.right_stick_button && !lastRightStick) autoAim = !autoAim;
        lastRightStick = gamepad1.right_stick_button;
        double maxStep = TURRET_SPEED_DEG_PER_S / TURRET_TRAVEL_DEG * dt;   // furthest the servo can really get in one loop
        if (gamepad1.dpad_left) { turret += TURRET_LEFT_SIGN * maxStep; autoAim = false; }
        if (gamepad1.dpad_right) { turret -= TURRET_LEFT_SIGN * maxStep; autoAim = false; }
        if (autoAim) {
            if (cellKnown) {
                // The camera rides on the turret, so the bearing is how many degrees the turret still has
                // to turn left. Correct a share of it on every new picture, never faster than the servo.
                if (freshFrame) {
                    double step = TURRET_LEFT_SIGN * cellBearing / TURRET_TRAVEL_DEG * AIM_GAIN;
                    turret += Math.max(-maxStep * 3.0, Math.min(maxStep * 3.0, step));
                }
            } else {
                // Nothing in view: sweep slowly from one end to the other until the cell shows up.
                turret += sweepDirection * maxStep * 0.6;
                if (turret >= TURRET_MAX) sweepDirection = -1.0;
                if (turret <= TURRET_MIN) sweepDirection = 1.0;
            }
        }
        turret = Math.max(TURRET_MIN, Math.min(TURRET_MAX, turret));
        boolean turretAtEnd = autoAim && cellKnown && (turret <= TURRET_MIN || turret >= TURRET_MAX) && Math.abs(cellBearing) > AIM_TOLERANCE_DEG;
        set(turretServo, turret);

        // ---- hood and flywheel speed ----
        if (gamepad1.x && !lastX) flywheelOn = !flywheelOn;
        double rpmStep = gamepad1.left_bumper ? 25.0 : 250.0;
        if (gamepad1.y && !lastY) manualRpm += rpmStep;
        if (gamepad1.a && !lastA) manualRpm -= rpmStep;
        if (gamepad1.left_stick_button && !lastLeftStick) nectarMode = !nectarMode;
        lastX = gamepad1.x;
        lastY = gamepad1.y;
        lastA = gamepad1.a;
        lastLeftStick = gamepad1.left_stick_button;
        manualRpm = Math.max(0.0, Math.min(MANUAL_RPM_LIMIT, manualRpm));

        double targetRpm = manualRpm;
        String shotNote = "by hand";
        if (autoAim && cellKnown) {
            double[] shot = lookUpShot(cellDistance);
            hood = shot[0];
            targetRpm = shot[1];
            shotNote = cellDistance < SHOT_TABLE[0][0] - 2.0 ? "TOO CLOSE for the table"
                : cellDistance > SHOT_TABLE[SHOT_TABLE.length - 1][0] + 2.0 ? "TOO FAR for the table" : "from the table";
        } else if (!autoAim) {
            if (gamepad1.dpad_up) hood += 0.4 * dt;
            if (gamepad1.dpad_down) hood -= 0.4 * dt;
        }
        hood = Math.max(0.0, Math.min(1.0, hood));
        set(hoodServo, HOOD_FLAT + hood * (HOOD_STEEP - HOOD_FLAT));
        if (nectarMode) targetRpm *= NECTAR_SPEED_FACTOR;
        double commandedRpm = flywheelOn ? targetRpm : 0.0;

        DcMotorEx[] shooters = {shooterLeft, shooterRight};
        double[] motorRpm = new double[2];   // each motor's own reading: + = the way it is told to turn
        for (int i = 0; i < 2; i++) {
            if (shooters[i] != null) motorRpm[i] = shooters[i].getVelocity() / SHOOTER_TICKS_PER_REV * 60.0;
        }
        // The flywheel's speed comes from one encoder, and both motors get the same power.
        double actualRpm = Math.abs(motorRpm[SHOOTER_SPEED_FROM_LEFT ? 0 : 1]);
        double shooterPower = flywheelPower(commandedRpm, actualRpm, now, dt);
        power(shooterLeft, shooterPower);
        power(shooterRight, shooterPower);
        // How far a ball pulls the speed down: the lowest reading in the last three seconds.
        if (now - dipSeenAt > 3.0 || actualRpm < dipRpm) {
            if (actualRpm < dipRpm || now - dipSeenAt > 3.0) dipSeenAt = now;
            dipRpm = actualRpm;
        }
        // What is wrong with the flywheel, if anything, once it has had a second to spin up.
        if (commandedRpm < 300.0) flywheelOnSince = now;
        String problem = "";
        if (now - flywheelOnSince > 1.0 && shooterLeft != null && shooterRight != null) {
            String chosen = SHOOTER_SPEED_FROM_LEFT ? "shooterLeft" : "shooterRight";
            double mine = motorRpm[SHOOTER_SPEED_FROM_LEFT ? 0 : 1], other = motorRpm[SHOOTER_SPEED_FROM_LEFT ? 1 : 0];
            boolean mineTurns = Math.abs(mine) > 150.0, otherTurns = Math.abs(other) > 150.0;
            if (!mineTurns && !otherTurns)
                problem = "NOT TURNING: jammed, or the two motors push against each other (flip ONE of the REVERSE_SHOOTER_... settings)";
            else if (!mineTurns)
                problem = chosen + " READS 0 but the other motor turns: its encoder cable is out. Change SHOOTER_SPEED_FROM_LEFT to " + !SHOOTER_SPEED_FROM_LEFT;
            else if (mine < 0)
                problem = "TURNING BACKWARDS: flip both REVERSE_SHOOTER_... settings";
            else if (otherTurns && Math.abs(Math.abs(other) - Math.abs(mine)) > 0.15 * Math.abs(mine))
                problem = "THE TWO MOTORS SHOW DIFFERENT SPEEDS. On one shaft they must be equal: an encoder is faulty, or something between them slips";
            else if (actualRpm < 0.7 * commandedRpm && commandedRpm < 3500.0)
                problem = "TOO SLOW: it cannot reach the speed. Take the balls out; if it is still slow, something is rubbing or the battery is low";
        }
        if (speedBlind && SHOOTER_HOLD_SPEED) problem = "NO SPEED READING for a moment (jam, or encoder cable): running on plain power until X is pressed off and on. " + problem;

        // ---- feeders and gate ----
        boolean shoot = gamepad1.right_trigger > 0.3;
        boolean feedUp = gamepad1.left_trigger > 0.3;
        boolean speedReady = flywheelOn && (!SHOOTER_HOLD_SPEED || speedBlind || Math.abs(actualRpm - targetRpm) <= SPEED_TOLERANCE * targetRpm);
        boolean aimReady = !autoAim || (cellKnown && Math.abs(cellBearing) <= AIM_TOLERANCE_DEG);
        boolean fire = shoot && speedReady && aimReady;
        // With a gate the feeders may run while it is shut (the balls wait at the neck). Without one, the
        // feeders are the only thing holding a ball back, so they wait for the shot to be ready.
        double feed = gamepad1.right_bumper ? -1.0 : (feedUp || fire || (shoot && gateServo != null)) ? 1.0 : 0.0;
        power(intakeA, feed);
        power(intakeB, feed);
        set(gateServo, fire ? GATE_OPEN : GATE_CLOSED);

        // ---- Driver Station ----
        telemetry.addData("Flywheel (X)", "%s   %.0f of %.0f rpm (%s)%s", flywheelOn ? "ON" : "OFF", actualRpm, commandedRpm, shotNote, nectarMode ? "  NECTAR" : "");
        telemetry.addData("Each motor", "shooterLeft %+.0f rpm   shooterRight %+.0f rpm   power %.0f %%", motorRpm[0], motorRpm[1], shooterPower * 100.0);
        telemetry.addData("Slowest in the last 3 s", "%.0f rpm  (how far a ball pulled it down; 0 = it stalled)", dipRpm);
        if (!problem.isEmpty()) telemetry.addData("FLYWHEEL PROBLEM", problem);
        telemetry.addData("Auto-aim", autoAim ? "ON" : "off");
        if (cellKnown) telemetry.addData("Camera", "%s  bearing %.1f  distance %.1f in  %d%% seen", cellName, cellBearing, cellDistance, cellPercent);
        else telemetry.addData("Camera", aprilTag == null ? "no camera" : "no scorable cell in view");
        telemetry.addData("Turret / hood", "%.3f / %.2f", turret, hood);
        if (turretAtEnd) telemetry.addData("TURRET AT ITS END", cellBearing > 0 ? "turn the robot LEFT" : "turn the robot RIGHT");
        telemetry.addData("Shot", fire ? "FIRING" : !flywheelOn ? "flywheel is off (X)" : !shoot ? (speedReady && aimReady ? "ready" : "not ready") : !speedReady ? "waiting for the flywheel" : "waiting for the aim");
        // The line to copy into SHOT_TABLE when shots from here go in.
        if (cellKnown) telemetry.addData("Table row", "{%.1f, %.2f, %.0f},", cellDistance, hood, nectarMode ? targetRpm / NECTAR_SPEED_FACTOR : targetRpm);
        else telemetry.addData("Table row", "needs the camera to see our raised cell (for the distance)");
        if (!missing.isEmpty()) telemetry.addData("NOT in this configuration", missing);
    }

    @Override
    public void stop() {
        if (visionPortal != null) visionPortal.close();
    }

    /**
     * The power for BOTH shooter motors that brings the flywheel to `wantedRpm` and keeps it there.
     * If the encoder shows nothing for a moment while power is on (a jam, or its cable is out), it stops
     * trusting it and falls back to plain power, so a dead encoder can never send the motors to full speed.
     */
    private double flywheelPower(double wantedRpm, double measuredRpm, double now, double dt) {
        if (wantedRpm <= 0.0) {
            speedSum = 0.0;
            speedBlind = false;
            speedSeenAt = now;
            return 0.0;
        }
        double base = Math.min(1.0, wantedRpm / SHOOTER_MAX_RPM);
        if (measuredRpm > 0.1 * wantedRpm) speedSeenAt = now;
        if (now - speedSeenAt > 0.7) speedBlind = true;
        if (!SHOOTER_HOLD_SPEED || speedBlind) return base;
        double shortfall = (wantedRpm - measuredRpm) / SHOOTER_MAX_RPM;
        // Only add up the shortfall once the speed is close, so spinning up from rest does not overshoot.
        if (Math.abs(shortfall) < 0.03) speedSum = Math.max(-0.15, Math.min(0.15, speedSum + shortfall * dt));
        return Math.max(0.0, Math.min(1.0, base + SHOOTER_KP * shortfall + SHOOTER_KI * speedSum));
    }

    /** Hood (0..1) and flywheel rpm for a distance, blended between the two nearest rows of the table. */
    static double[] lookUpShot(double distance) {
        double[][] t = SHOT_TABLE;
        if (distance <= t[0][0]) return new double[]{t[0][1], t[0][2]};
        for (int i = 1; i < t.length; i++) {
            if (distance <= t[i][0]) {
                double k = (distance - t[i - 1][0]) / (t[i][0] - t[i - 1][0]);
                return new double[]{t[i - 1][1] + k * (t[i][1] - t[i - 1][1]), t[i - 1][2] + k * (t[i][2] - t[i - 1][2])};
            }
        }
        return new double[]{t[t.length - 1][1], t[t.length - 1][2]};
    }

    /** A motor from the configuration, or null (and a note for the Driver Station) when it is not there. */
    private DcMotorEx motor(String name, boolean reversed) {
        DcMotorEx m = hardwareMap.tryGet(DcMotorEx.class, name);
        if (m == null) missing.add(name);
        else m.setDirection(reversed ? DcMotorSimple.Direction.REVERSE : DcMotorSimple.Direction.FORWARD);
        return m;
    }

    private Servo servo(String name) {
        Servo s = hardwareMap.tryGet(Servo.class, name);
        if (s == null) missing.add(name);
        return s;
    }

    private static void power(DcMotorEx m, double p) {
        if (m != null) m.setPower(p);
    }

    private static void set(Servo s, double position) {
        if (s != null) s.setPosition(Math.max(0.0, Math.min(1.0, position)));
    }
}
