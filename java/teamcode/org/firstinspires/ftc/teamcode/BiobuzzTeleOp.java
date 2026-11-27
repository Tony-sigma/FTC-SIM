package org.firstinspires.ftc.teamcode;

import com.qualcomm.hardware.gobilda.GoBildaPinpointDriver;
import com.qualcomm.hardware.rev.RevHubOrientationOnRobot;
import com.qualcomm.robotcore.eventloop.opmode.OpMode;
import com.qualcomm.robotcore.eventloop.opmode.TeleOp;
import com.qualcomm.robotcore.hardware.DcMotor;
import com.qualcomm.robotcore.hardware.DcMotorEx;
import com.qualcomm.robotcore.hardware.DcMotorSimple;
import com.qualcomm.robotcore.hardware.IMU;
import com.qualcomm.robotcore.hardware.Servo;
import org.firstinspires.ftc.robotcore.external.hardware.camera.WebcamName;
import org.firstinspires.ftc.robotcore.external.navigation.AngleUnit;
import org.firstinspires.ftc.robotcore.external.navigation.DistanceUnit;
import org.firstinspires.ftc.robotcore.external.navigation.Pose2D;
import org.firstinspires.ftc.vision.VisionPortal;
import org.firstinspires.ftc.vision.apriltag.AprilTagClusterDetection;
import org.firstinspires.ftc.vision.apriltag.AprilTagDetection;
import org.firstinspires.ftc.vision.apriltag.AprilTagProcessor;
import java.util.ArrayList;
import java.util.List;

/**
 * BIOBUZZ driver-controlled OpMode. Ordinary FTC code: the same file runs on the Control Hub and in
 * the simulator.
 *
 *   Left stick   drive / strafe          Right stick   turn
 *   Left trigger intake (both sides)     Right trigger shoot (waits until the flywheel and the aim are ready)
 *   Right bumper spit balls back out     Left bumper   slow mode
 *   Right stick click  AUTO-AIM on/off: the camera keeps the turret on our hive's raised cell and sets
 *                      the hood and the flywheel speed from the distance
 *   D-pad left/right   turret by hand (switches auto-aim off)
 *   D-pad up/down      hood by hand (only while auto-aim is off)
 *   Left stick click   NECTAR mode on/off (flywheel a little faster, for the heavier ball)
 *   A / B        front / back lever      Y  field-centric on/off     X  reset heading
 *   Second gamepad, D-pad up/down: flywheel speed for shots by hand (for building the shot table)
 *
 * Any device that is not in the active robot configuration is simply skipped and listed on the Driver
 * Station, so this also runs on a half-built robot.
 */
@TeleOp(name = "Biobuzz TeleOp", group = "Biobuzz")
public class BiobuzzTeleOp extends OpMode {

    // =====================================================================================================
    //  ROBOT SETTINGS. Check every one of these on the real robot with the "Test: ..." OpModes first.
    // =====================================================================================================

    /** Our alliance: "RED" or "BLUE". The camera only aims at hive cells of this colour. */
    static final String OUR_ALLIANCE = "RED";

    // ---- Drive (check with "Test: Drive Motors": every wheel must roll forward on a positive power) ----
    static final boolean REVERSE_LEFT_SIDE = true;    // left motors are mounted mirrored
    static final boolean REVERSE_RIGHT_SIDE = false;
    static final double SLOW_SCALE = 0.4;

    // ---- Control Hub mounting, for the heading (check with "Test: Sensors") ----
    static final RevHubOrientationOnRobot.LogoFacingDirection HUB_LOGO = RevHubOrientationOnRobot.LogoFacingDirection.UP;
    static final RevHubOrientationOnRobot.UsbFacingDirection HUB_USB = RevHubOrientationOnRobot.UsbFacingDirection.FORWARD;

    // ---- Intakes / feeders (check with "Test: Intakes": positive must pull balls IN and up) ----
    static final boolean REVERSE_INTAKE_A = false;
    static final boolean REVERSE_INTAKE_B = false;

    // ---- Shooter (check with "Test: Shooter": both motors must turn the flywheel the SAME way) ----
    static final boolean REVERSE_SHOOTER_LEFT = false;
    static final boolean REVERSE_SHOOTER_RIGHT = false;
    /**
     * true = the hub holds the flywheel speed (RUN_USING_ENCODER). Every ball slows the wheels (a nectar
     * three times as much as a pollen) and the hub pushes at full voltage to get the speed back; with
     * plain power a stream of shots gets weaker and weaker. BOTH shooter motors need their encoder
     * cables plugged in. If one is missing, set this to false.
     */
    static final boolean SHOOTER_HOLD_SPEED = true;
    static final double SHOOTER_TICKS_PER_REV = 28.0;   // bare goBILDA Yellow Jacket motor
    static final double SHOOTER_MAX_RPM = 6000.0;
    /** Speed-hold tuning, starting values: F = 32767 / (max ticks per second), then raise P until it recovers fast without buzzing. */
    static final double SHOOTER_P = 10.0, SHOOTER_I = 0.0, SHOOTER_D = 0.0, SHOOTER_F = 11.7;
    /** Flywheel speed for shots by hand (auto-aim off). Change it live with the second gamepad's D-pad. */
    static final double MANUAL_RPM = 1400.0;
    /** A nectar needs the flywheel about this much faster than a pollen for the same shot. */
    static final double NECTAR_SPEED_FACTOR = 1.04;
    /** Shoot only while the flywheel is within this fraction of the speed the shot needs. */
    static final double SPEED_TOLERANCE = 0.04;

    // ---- Gate servo at the neck (check with "Test: Servos"). No gate on the robot? Leave it out of the configuration. ----
    static final double GATE_CLOSED = 0.0, GATE_OPEN = 1.0;

    // ---- Turret servo (check with "Test: Turret") ----
    /** Servo position that points the shooter straight ahead. */
    static final double TURRET_CENTER = 0.5;
    /** The furthest the servo may go each way before something hits. */
    static final double TURRET_MIN = 0.0, TURRET_MAX = 1.0;
    /**
     * How many degrees the TURRET turns when the servo goes from position 0 to 1: servo travel x 15 / 70.
     * A 300 degree servo gives 64.3. A 5-turn (1800 degree) servo would give 385.7.
     */
    static final double TURRET_TRAVEL_DEG = 64.3;
    /** +1 if a bigger servo position turns the turret LEFT (counter-clockwise seen from above), -1 if it turns it right. */
    static final double TURRET_LEFT_SIGN = 1.0;
    /** How fast the turret can really turn. Torque servo about 50 deg/s, Speed servo about 115. The aim never asks for more. */
    static final double TURRET_SPEED_DEG_PER_S = 50.0;
    /** Share of the aiming error corrected on each new camera frame. Lower it if the turret wobbles around the target. */
    static final double AIM_GAIN = 0.35;
    /** Shoot only while the camera says the turret is within this many degrees of the cell. */
    static final double AIM_TOLERANCE_DEG = 3.0;

    // ---- Hood servo (check with "Test: Hood") ----
    /** Servo position with the hood at its FLATTEST shot, and at its STEEPEST shot. */
    static final double HOOD_FLAT = 0.0, HOOD_STEEP = 1.0;

    // ---- Lever servos (check with "Test: Levers") ----
    static final double LEVER_FRONT_IN = 0.0, LEVER_FRONT_OUT = 1.0;
    static final double LEVER_BACK_IN = 0.0, LEVER_BACK_OUT = 1.0;

    // ---- Odometry: goBILDA Pinpoint + two 4-Bar pods (check with "Test: Odometry", then copy its numbers here) ----
    static final String PINPOINT_NAME = "pinpoint";
    /** How far LEFT of the robot's centre the forward (X) pod is, in mm. Right of centre = negative. From the CAD. */
    static final double X_POD_OFFSET_MM = -131.0;
    /** How far FORWARD of the robot's centre the sideways (Y) pod is, in mm. Behind the centre = negative. From the CAD. */
    static final double Y_POD_OFFSET_MM = -88.8;
    static final GoBildaPinpointDriver.EncoderDirection X_POD_DIRECTION = GoBildaPinpointDriver.EncoderDirection.FORWARD;
    static final GoBildaPinpointDriver.EncoderDirection Y_POD_DIRECTION = GoBildaPinpointDriver.EncoderDirection.FORWARD;

    // ---- Camera on the shooter ----
    static final String CAMERA_NAME = "Webcam 1";
    /** An Arducam needs its lens calibration for a correct distance. Fill these in and set the switch to true. */
    static final boolean USE_LENS_CALIBRATION = false;
    static final double LENS_FX = 0.0, LENS_FY = 0.0, LENS_CX = 0.0, LENS_CY = 0.0;

    /**
     * THE SHOT TABLE: for a distance from the camera to the cell's opening (inches), how steep the hood
     * must be (0 = flattest, 1 = steepest) and how fast the flywheel must turn (rpm) for a POLLEN.
     * In between two rows the code blends them.
     *
     * These numbers come from the simulator, which guesses how much speed the wheels really give a ball.
     * They are a STARTING POINT. On the real field: auto-aim off, stand at a known distance (telemetry
     * shows it), set the hood with the D-pad and the speed with the second gamepad, and when shots go in,
     * write that row down here.
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

    private DcMotorEx frontLeft, frontRight, backLeft, backRight;
    private DcMotorEx intakeA, intakeB, shooterLeft, shooterRight;
    private Servo turretServo, hoodServo, gateServo, leverLeft, leverRight;
    private IMU imu;
    private VisionPortal visionPortal;
    private AprilTagProcessor aprilTag;
    private final List<String> missing = new ArrayList<>();
    private GoBildaPinpointDriver pinpoint;
    private double odoX, odoY, odoHeading, odoTime, speedInPerS;

    private double turret = TURRET_CENTER, hood = 0.5, manualRpm = MANUAL_RPM;
    private boolean fieldCentric = true, autoAim = false, nectarMode = false;
    private boolean leverFrontOut = false, leverBackOut = false;
    private boolean lastA, lastB, lastY, lastRightStick, lastLeftStick, lastUp2, lastDown2;
    private double sweepDirection = 1.0, lastLoopTime = 0.0;
    // What the camera last saw of our raised cell.
    private boolean seesCell = false;
    private double cellBearing = 0.0, cellDistance = 0.0, cellSeenAt = -10.0;
    private String cellName = "";
    private int cellPercent = 0;

    @Override
    public void init() {
        frontLeft = motor("frontLeft", REVERSE_LEFT_SIDE);
        backLeft = motor("backLeft", REVERSE_LEFT_SIDE);
        frontRight = motor("frontRight", REVERSE_RIGHT_SIDE);
        backRight = motor("backRight", REVERSE_RIGHT_SIDE);
        for (DcMotorEx m : new DcMotorEx[]{frontLeft, frontRight, backLeft, backRight}) {
            if (m != null) m.setZeroPowerBehavior(DcMotor.ZeroPowerBehavior.BRAKE);
        }

        intakeA = motor("intakeA", REVERSE_INTAKE_A);
        intakeB = motor("intakeB", REVERSE_INTAKE_B);
        shooterLeft = motor("shooterLeft", REVERSE_SHOOTER_LEFT);
        shooterRight = motor("shooterRight", REVERSE_SHOOTER_RIGHT);
        for (DcMotorEx m : new DcMotorEx[]{shooterLeft, shooterRight}) {
            if (m == null) continue;
            m.setZeroPowerBehavior(DcMotor.ZeroPowerBehavior.FLOAT);
            if (SHOOTER_HOLD_SPEED) {
                m.setMode(DcMotor.RunMode.RUN_USING_ENCODER);
                m.setVelocityPIDFCoefficients(SHOOTER_P, SHOOTER_I, SHOOTER_D, SHOOTER_F);
            } else {
                m.setMode(DcMotor.RunMode.RUN_WITHOUT_ENCODER);
            }
        }

        turretServo = servo("turretServo");
        hoodServo = servo("hoodServo");
        gateServo = servo("gateServo");
        leverLeft = servo("leverLeft");
        leverRight = servo("leverRight");

        imu = hardwareMap.tryGet(IMU.class, "imu");
        if (imu == null) {
            missing.add("imu");
        } else {
            imu.initialize(new IMU.Parameters(new RevHubOrientationOnRobot(HUB_LOGO, HUB_USB)));
            imu.resetYaw();
        }

        // Odometry. Position 0, 0 and heading 0 are where the robot stands when INIT is pressed:
        // X counts inches forward from there, Y inches to the left. Keep the robot still during INIT.
        pinpoint = hardwareMap.tryGet(GoBildaPinpointDriver.class, PINPOINT_NAME);
        if (pinpoint == null) {
            missing.add(PINPOINT_NAME);
        } else {
            pinpoint.setOffsets(X_POD_OFFSET_MM, Y_POD_OFFSET_MM, DistanceUnit.MM);
            pinpoint.setEncoderResolution(GoBildaPinpointDriver.GoBildaOdometryPods.goBILDA_4_BAR_POD);
            pinpoint.setEncoderDirections(X_POD_DIRECTION, Y_POD_DIRECTION);
            pinpoint.resetPosAndIMU();
        }

        // The camera on the shooter, looking for the AprilTags under the hive cells.
        WebcamName webcam = hardwareMap.tryGet(WebcamName.class, CAMERA_NAME);
        if (webcam == null) {
            missing.add(CAMERA_NAME);
        } else {
            AprilTagProcessor.Builder tags = new AprilTagProcessor.Builder();
            if (USE_LENS_CALIBRATION) tags.setLensIntrinsics(LENS_FX, LENS_FY, LENS_CX, LENS_CY);
            aprilTag = tags.build();
            visionPortal = new VisionPortal.Builder().setCamera(webcam).addProcessor(aprilTag).build();
        }

        telemetry.addData("Status", "Ready. Press start.");
        if (!missing.isEmpty()) telemetry.addData("NOT in this configuration", missing);
    }

    @Override
    public void loop() {
        double now = getRuntime();
        double dt = Math.max(0.001, Math.min(0.1, now - lastLoopTime));
        lastLoopTime = now;

        // ---- driving ----
        double forward = -gamepad1.left_stick_y;   // stick forward is negative
        double strafe = gamepad1.left_stick_x;
        double turn = gamepad1.right_stick_x;
        double heading = imu == null ? 0.0 : imu.getRobotYawPitchRollAngles().getYaw(AngleUnit.RADIANS);

        if (gamepad1.y && !lastY) fieldCentric = !fieldCentric;
        lastY = gamepad1.y;
        if (gamepad1.x && imu != null) imu.resetYaw();
        if (fieldCentric && imu != null) {
            // heading is counter-clockwise (left turn = positive), as the IMU reports it.
            double f = forward * Math.cos(heading) - strafe * Math.sin(heading);
            double s = forward * Math.sin(heading) + strafe * Math.cos(heading);
            forward = f;
            strafe = s;
        }
        double scale = gamepad1.left_bumper ? SLOW_SCALE : 1.0;
        double biggest = Math.max(Math.abs(forward) + Math.abs(strafe) + Math.abs(turn), 1.0);
        power(frontLeft, (forward + strafe + turn) / biggest * scale);
        power(frontRight, (forward - strafe - turn) / biggest * scale);
        power(backLeft, (forward - strafe + turn) / biggest * scale);
        power(backRight, (forward + strafe - turn) / biggest * scale);

        // ---- odometry: where the robot is and how fast it is going ----
        if (pinpoint != null) {
            pinpoint.update();   // must be called every loop, or the numbers never change
            Pose2D pose = pinpoint.getPosition();
            double x = pose.getX(DistanceUnit.INCH), y = pose.getY(DistanceUnit.INCH);
            double time = getRuntime();
            if (odoTime > 0 && time > odoTime) speedInPerS = Math.hypot(x - odoX, y - odoY) / (time - odoTime);
            odoX = x;
            odoY = y;
            odoHeading = pose.getHeading(AngleUnit.DEGREES);
            odoTime = time;
        }

        // ---- camera: find our raised cell ----
        // Each hive cell has a cluster of four AprilTags, and the SDK reports a cluster as one detection
        // that points at the centre of the cell's opening. Ours has a name starting with our colour, and
        // the raised cell (the one we can score in) is the right way up: roll between -90 and 90.
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
        if (gamepad1.left_stick_button && !lastLeftStick) nectarMode = !nectarMode;
        lastLeftStick = gamepad1.left_stick_button;
        if (gamepad2.dpad_up && !lastUp2) manualRpm += 25.0;
        if (gamepad2.dpad_down && !lastDown2) manualRpm -= 25.0;
        lastUp2 = gamepad2.dpad_up;
        lastDown2 = gamepad2.dpad_down;
        manualRpm = Math.max(0.0, Math.min(SHOOTER_MAX_RPM, manualRpm));

        double targetRpm = manualRpm;
        String shotNote = "by hand";
        if (autoAim && cellKnown) {
            // From the table: the two rows around this distance, blended.
            double[] shot = lookUpShot(cellDistance);
            hood = shot[0];
            targetRpm = shot[1];
            shotNote = cellDistance < SHOT_TABLE[0][0] - 2.0 ? "TOO CLOSE - back away"
                : cellDistance > SHOT_TABLE[SHOT_TABLE.length - 1][0] + 2.0 ? "TOO FAR - drive closer" : "from the table";
        } else if (!autoAim) {
            if (gamepad1.dpad_up) hood += 0.6 * dt;
            if (gamepad1.dpad_down) hood -= 0.6 * dt;
        }
        hood = Math.max(0.0, Math.min(1.0, hood));
        set(hoodServo, HOOD_FLAT + hood * (HOOD_STEEP - HOOD_FLAT));
        if (nectarMode) targetRpm *= NECTAR_SPEED_FACTOR;

        double actualRpm = 0.0;
        for (DcMotorEx m : new DcMotorEx[]{shooterLeft, shooterRight}) {
            if (m == null) continue;
            if (SHOOTER_HOLD_SPEED) m.setVelocity(targetRpm / 60.0 * SHOOTER_TICKS_PER_REV);   // ticks per second
            else m.setPower(targetRpm / SHOOTER_MAX_RPM);
            actualRpm = Math.max(actualRpm, Math.abs(m.getVelocity()) / SHOOTER_TICKS_PER_REV * 60.0);
        }

        // ---- intake, feeders, gate ----
        boolean shoot = gamepad1.right_trigger > 0.3;
        boolean intake = gamepad1.left_trigger > 0.3;
        boolean speedReady = !SHOOTER_HOLD_SPEED || Math.abs(actualRpm - targetRpm) <= SPEED_TOLERANCE * targetRpm;
        boolean aimReady = !autoAim || (cellKnown && Math.abs(cellBearing) <= AIM_TOLERANCE_DEG);
        boolean fire = shoot && speedReady && aimReady;
        // With a gate the feeders may run while it is shut (the balls wait at the neck). Without one, the
        // feeders are the only thing holding a ball back, so they wait for the shot to be ready.
        double feed = gamepad1.right_bumper ? -1.0 : (intake || fire || (shoot && gateServo != null)) ? 1.0 : 0.0;
        power(intakeA, feed);
        power(intakeB, feed);
        set(gateServo, fire ? GATE_OPEN : GATE_CLOSED);

        // ---- levers ----
        if (gamepad1.a && !lastA) leverFrontOut = !leverFrontOut;
        if (gamepad1.b && !lastB) leverBackOut = !leverBackOut;
        lastA = gamepad1.a;
        lastB = gamepad1.b;
        set(leverLeft, leverFrontOut ? LEVER_FRONT_OUT : LEVER_FRONT_IN);
        set(leverRight, leverBackOut ? LEVER_BACK_OUT : LEVER_BACK_IN);

        // ---- Driver Station ----
        telemetry.addData("Drive", fieldCentric && imu != null ? "field-centric" : "robot-centric");
        telemetry.addData("Heading", "%.1f deg", Math.toDegrees(heading));
        telemetry.addData("Auto-aim", autoAim ? "ON" : "off");
        if (cellKnown) telemetry.addData("Camera", "%s  bearing %.1f  distance %.1f in  %d%% seen", cellName, cellBearing, cellDistance, cellPercent);
        else telemetry.addData("Camera", aprilTag == null ? "no camera" : "no scorable cell in view");
        telemetry.addData("Turret / hood", "%.3f / %.2f", turret, hood);
        if (turretAtEnd) telemetry.addData("TURRET AT ITS END", cellBearing > 0 ? "turn the robot LEFT" : "turn the robot RIGHT");
        telemetry.addData("Flywheel", "%.0f of %.0f rpm (%s)%s", actualRpm, targetRpm, shotNote, nectarMode ? "  NECTAR" : "");
        telemetry.addData("Shot", fire ? "FIRING" : !shoot ? (speedReady && aimReady ? "ready" : "not ready") : !speedReady ? "waiting for the flywheel" : "waiting for the aim");
        if (pinpoint != null) {
            telemetry.addData("Position", "x %.1f in  y %.1f in  facing %.1f deg", odoX, odoY, odoHeading);
            telemetry.addData("Speed", "%.1f in/s  (odometry %s)", speedInPerS, pinpoint.getDeviceStatus());
        }
        if (frontLeft != null) telemetry.addData("Front left encoder", frontLeft.getCurrentPosition());
        if (!missing.isEmpty()) telemetry.addData("NOT in this configuration", missing);
    }

    @Override
    public void stop() {
        if (visionPortal != null) visionPortal.close();
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
