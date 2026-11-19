package org.firstinspires.ftc.teamcode;

import com.qualcomm.hardware.rev.RevHubOrientationOnRobot;
import com.qualcomm.robotcore.eventloop.opmode.OpMode;
import com.qualcomm.robotcore.eventloop.opmode.TeleOp;
import com.qualcomm.robotcore.hardware.DcMotor;
import com.qualcomm.robotcore.hardware.DcMotorSimple;
import com.qualcomm.robotcore.hardware.IMU;
import com.qualcomm.robotcore.hardware.Servo;
import org.firstinspires.ftc.robotcore.external.hardware.camera.WebcamName;
import org.firstinspires.ftc.robotcore.external.navigation.AngleUnit;
import org.firstinspires.ftc.vision.VisionPortal;
import org.firstinspires.ftc.vision.apriltag.AprilTagDetection;
import org.firstinspires.ftc.vision.apriltag.AprilTagProcessor;

/**
 * Sample driver-controlled OpMode. It is ordinary FTC code: the same file runs on the Control Hub
 * and in the simulator.
 *
 *   Left stick   drive / strafe          Right stick  turn
 *   Left trigger intake (both sides)     Right trigger shoot
 *   Right bumper spit pollen back out    Left bumper   slow mode
 *   D-pad left/right  turret             D-pad up/down hood
 *   Right stick click  turret auto-aim on/off (the camera keeps the turret on our hive's AprilTag)
 *   A / B        front / back lever      Y  field-centric on/off     X  reset heading
 */
@TeleOp(name = "Biobuzz TeleOp", group = "Biobuzz")
public class BiobuzzTeleOp extends OpMode {
    private DcMotor frontLeft, frontRight, backLeft, backRight;
    private DcMotor intakeA, intakeB, shooterLeft, shooterRight;
    private Servo turretServo, hoodServo, gateServo, leverLeft, leverRight;
    private IMU imu;
    private VisionPortal visionPortal;
    private AprilTagProcessor aprilTag;

    private double turret = 0.5, hood = 0.5;
    private boolean fieldCentric = true, leverFrontOut = false, leverBackOut = false;
    private boolean lastA, lastB, lastY, lastStick;
    /** AprilTag IDs under OUR hive's two cells. PLACEHOLDERS: use the numbers from the game manual. */
    private static final int[] OUR_TAGS = {1, 2};
    /** The 6000 rpm shooter is far faster than a shot needs; about a fifth of full power reaches the hive. Tune this. */
    private static final double SHOOTER_POWER = 0.22;
    private boolean autoAim = false;
    private static final double sweep = 0.003;

    @Override
    public void init() {
        frontLeft = hardwareMap.get(DcMotor.class, "frontLeft");
        frontRight = hardwareMap.get(DcMotor.class, "frontRight");
        backLeft = hardwareMap.get(DcMotor.class, "backLeft");
        backRight = hardwareMap.get(DcMotor.class, "backRight");
        // The left motors are mounted mirrored, so they must be reversed for "positive = forward".
        frontLeft.setDirection(DcMotorSimple.Direction.REVERSE);
        backLeft.setDirection(DcMotorSimple.Direction.REVERSE);
        for (DcMotor m : new DcMotor[]{frontLeft, frontRight, backLeft, backRight}) {
            m.setZeroPowerBehavior(DcMotor.ZeroPowerBehavior.BRAKE);
        }

        intakeA = hardwareMap.get(DcMotor.class, "intakeA");
        intakeB = hardwareMap.get(DcMotor.class, "intakeB");
        shooterLeft = hardwareMap.get(DcMotor.class, "shooterLeft");
        shooterRight = hardwareMap.get(DcMotor.class, "shooterRight");

        turretServo = hardwareMap.get(Servo.class, "turretServo");
        hoodServo = hardwareMap.get(Servo.class, "hoodServo");
        gateServo = hardwareMap.get(Servo.class, "gateServo");
        leverLeft = hardwareMap.get(Servo.class, "leverLeft");
        leverRight = hardwareMap.get(Servo.class, "leverRight");

        imu = hardwareMap.get(IMU.class, "imu");
        imu.initialize(new IMU.Parameters(new RevHubOrientationOnRobot(
            RevHubOrientationOnRobot.LogoFacingDirection.UP, RevHubOrientationOnRobot.UsbFacingDirection.FORWARD)));
        imu.resetYaw();

        // The main camera on the shooter, looking for AprilTags.
        // On the real robot an Arducam also needs .setLensIntrinsics(fx, fy, cx, cy) from its calibration.
        aprilTag = new AprilTagProcessor.Builder().build();
        visionPortal = new VisionPortal.Builder()
            .setCamera(hardwareMap.get(WebcamName.class, "Webcam 1"))
            .addProcessor(aprilTag)
            .build();

        telemetry.addData("Status", "Ready. Press start.");
    }

    @Override
    public void loop() {
        // ---- driving ----
        double forward = -gamepad1.left_stick_y;   // stick forward is negative
        double strafe = gamepad1.left_stick_x;
        double turn = gamepad1.right_stick_x;
        double heading = imu.getRobotYawPitchRollAngles().getYaw(AngleUnit.RADIANS);

        if (gamepad1.y && !lastY) fieldCentric = !fieldCentric;
        lastY = gamepad1.y;
        if (gamepad1.x) imu.resetYaw();
        if (fieldCentric) {
            double f = forward * Math.cos(heading) + strafe * Math.sin(heading);
            double s = -forward * Math.sin(heading) + strafe * Math.cos(heading);
            forward = f;
            strafe = s;
        }
        double scale = gamepad1.left_bumper ? 0.4 : 1.0;
        double biggest = Math.max(Math.abs(forward) + Math.abs(strafe) + Math.abs(turn), 1.0);
        frontLeft.setPower((forward + strafe + turn) / biggest * scale);
        frontRight.setPower((forward - strafe - turn) / biggest * scale);
        backLeft.setPower((forward - strafe + turn) / biggest * scale);
        backRight.setPower((forward + strafe - turn) / biggest * scale);

        // ---- pollen ----
        boolean shoot = gamepad1.right_trigger > 0.3;
        boolean intake = gamepad1.left_trigger > 0.3;
        double feed = gamepad1.right_bumper ? -1.0 : ((shoot || intake) ? 1.0 : 0.0);
        intakeA.setPower(feed);
        intakeB.setPower(feed);
        shooterLeft.setPower(SHOOTER_POWER);          // flywheel always spinning
        shooterRight.setPower(SHOOTER_POWER);
        gateServo.setPosition(shoot ? 1.0 : 0.0);     // the gate lets pollen through only while shooting

        // ---- turret, hood, levers ----
        if (gamepad1.right_stick_button && !lastStick) autoAim = !autoAim;
        lastStick = gamepad1.right_stick_button;
        // Pick a tag in view that belongs to our hive.
        AprilTagDetection tag = null;
        for (AprilTagDetection d : aprilTag.getDetections()) {
            if (tag == null && d.metadata != null && (d.id == OUR_TAGS[0] || d.id == OUR_TAGS[1])) tag = d;
        }
        boolean seesTag = tag != null;
        if (gamepad1.dpad_left) { turret += 0.004; autoAim = false; }
        if (gamepad1.dpad_right) { turret -= 0.004; autoAim = false; }
        if (autoAim) {
            if (seesTag) {
                // bearing = how many degrees the camera must turn LEFT to face the tag. One full servo
                // travel is 360 degrees of turret and a bigger position turns it left, so add a share of it.
                turret += tag.ftcPose.bearing / 360.0 * 0.2;
            } else {
                // Nothing in view: keep turning the turret until a tag shows up.
                turret += sweep;
            }
            // Servo positions 0 and 1 point the turret the same way (one full turn apart), so going past
            // one end continues from the other.
            if (turret > 1.0) turret -= 1.0;
            if (turret < 0.0) turret += 1.0;
        }
        if (gamepad1.dpad_up) hood += 0.01;
        if (gamepad1.dpad_down) hood -= 0.01;
        turret = Math.max(0.0, Math.min(1.0, turret));
        hood = Math.max(0.0, Math.min(1.0, hood));
        turretServo.setPosition(turret);
        hoodServo.setPosition(hood);

        if (gamepad1.a && !lastA) leverFrontOut = !leverFrontOut;
        if (gamepad1.b && !lastB) leverBackOut = !leverBackOut;
        lastA = gamepad1.a;
        lastB = gamepad1.b;
        leverLeft.setPosition(leverFrontOut ? 1.0 : 0.0);
        leverRight.setPosition(leverBackOut ? 1.0 : 0.0);

        telemetry.addData("Drive", fieldCentric ? "field-centric" : "robot-centric");
        telemetry.addData("Heading", "%.1f deg", Math.toDegrees(heading));
        telemetry.addData("Turret / hood", "%.2f / %.2f", turret, hood);
        telemetry.addData("Auto-aim", autoAim ? "ON" : "off");
        if (seesTag) telemetry.addData("Camera", "tag %d  bearing %.1f  range %.0f in", tag.id, tag.ftcPose.bearing, tag.ftcPose.range);
        else telemetry.addData("Camera", "no tag");
        telemetry.addData("Front left encoder", frontLeft.getCurrentPosition());
    }

    @Override
    public void stop() {
        visionPortal.close();
    }
}
