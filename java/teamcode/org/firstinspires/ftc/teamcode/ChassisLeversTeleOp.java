package org.firstinspires.ftc.teamcode;

import com.qualcomm.hardware.gobilda.GoBildaPinpointDriver;
import com.qualcomm.hardware.rev.RevHubOrientationOnRobot;
import com.qualcomm.robotcore.eventloop.opmode.OpMode;
import com.qualcomm.robotcore.eventloop.opmode.TeleOp;
import com.qualcomm.robotcore.hardware.DcMotor;
import com.qualcomm.robotcore.hardware.DcMotorSimple;
import com.qualcomm.robotcore.hardware.IMU;
import com.qualcomm.robotcore.hardware.Servo;
import org.firstinspires.ftc.robotcore.external.navigation.AngleUnit;
import org.firstinspires.ftc.robotcore.external.navigation.DistanceUnit;
import org.firstinspires.ftc.robotcore.external.navigation.Pose2D;

/**
 * Only the chassis, the two levers (two servos each) and the odometry readout. Nothing else on the robot is touched.
 *
 *   Left stick   drive / strafe          Right stick   turn
 *   Left bumper  slow mode (hold)
 *   A            front lever out / in    B             back lever out / in
 *   Y            field-centric on / off  X             reset heading (robot facing away from you)
 *
 * Names needed in the robot configuration:
 *   motors  frontLeft, frontRight, backLeft, backRight
 *   servos  leverFrontLeft, leverFrontRight (the two on the front lever)
 *           leverBackLeft, leverBackRight (the two on the back lever)
 *   the Control Hub's built-in IMU, called "imu" (only needed for field-centric driving)
 *   the goBILDA Pinpoint odometry computer, called "pinpoint" (optional: shows position and speed)
 */
@TeleOp(name = "Chassis + Levers", group = "Biobuzz")
public class ChassisLeversTeleOp extends OpMode {

    // ================= ROBOT SETTINGS: check these on the real robot =================

    // Every wheel must roll FORWARD on a positive power (check with "Test: Drive Motors").
    static final boolean REVERSE_LEFT_SIDE = true;    // left motors are mounted mirrored
    static final boolean REVERSE_RIGHT_SIDE = false;
    static final double SLOW_SCALE = 0.4;

    // How the Control Hub is mounted, for the heading.
    static final RevHubOrientationOnRobot.LogoFacingDirection HUB_LOGO = RevHubOrientationOnRobot.LogoFacingDirection.UP;
    static final RevHubOrientationOnRobot.UsbFacingDirection HUB_USB = RevHubOrientationOnRobot.UsbFacingDirection.FORWARD;

    // Each lever is turned by TWO servos, one at each end of its bar. They face each other, so one of each
    // pair has to be reversed or the two fight instead of moving. CHECK EACH SERVO ALONE FIRST with
    // "Test: Levers" and the other servo of the pair unplugged from the hub.
    static final boolean REVERSE_LEVER_FRONT_LEFT = false, REVERSE_LEVER_FRONT_RIGHT = true;
    static final boolean REVERSE_LEVER_BACK_LEFT = false, REVERSE_LEVER_BACK_RIGHT = true;
    // Positions (the same number goes to both servos of a lever): folded in, and out working a flower.
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

    // ==================================================================================

    private DcMotor frontLeft, frontRight, backLeft, backRight;
    private Servo[] leverFront, leverBack;   // the two servos of each lever
    private IMU imu;
    private GoBildaPinpointDriver pinpoint;
    private double odoX, odoY, odoHeading, odoTime, speedInPerS;

    private boolean fieldCentric = true, leverFrontOut = false, leverBackOut = false;
    private boolean lastA, lastB, lastY;

    @Override
    public void init() {
        frontLeft = hardwareMap.get(DcMotor.class, "frontLeft");
        frontRight = hardwareMap.get(DcMotor.class, "frontRight");
        backLeft = hardwareMap.get(DcMotor.class, "backLeft");
        backRight = hardwareMap.get(DcMotor.class, "backRight");
        frontLeft.setDirection(REVERSE_LEFT_SIDE ? DcMotorSimple.Direction.REVERSE : DcMotorSimple.Direction.FORWARD);
        backLeft.setDirection(REVERSE_LEFT_SIDE ? DcMotorSimple.Direction.REVERSE : DcMotorSimple.Direction.FORWARD);
        frontRight.setDirection(REVERSE_RIGHT_SIDE ? DcMotorSimple.Direction.REVERSE : DcMotorSimple.Direction.FORWARD);
        backRight.setDirection(REVERSE_RIGHT_SIDE ? DcMotorSimple.Direction.REVERSE : DcMotorSimple.Direction.FORWARD);
        for (DcMotor m : new DcMotor[]{frontLeft, frontRight, backLeft, backRight}) {
            m.setZeroPowerBehavior(DcMotor.ZeroPowerBehavior.BRAKE);   // stop quickly when the sticks are let go
        }

        // The levers and the IMU may be missing: the chassis still drives, and the screen says what is not there.
        leverFront = new Servo[]{leverServo("leverFrontLeft", REVERSE_LEVER_FRONT_LEFT), leverServo("leverFrontRight", REVERSE_LEVER_FRONT_RIGHT)};
        leverBack = new Servo[]{leverServo("leverBackLeft", REVERSE_LEVER_BACK_LEFT), leverServo("leverBackRight", REVERSE_LEVER_BACK_RIGHT)};
        imu = hardwareMap.tryGet(IMU.class, "imu");
        if (imu != null) {
            imu.initialize(new IMU.Parameters(new RevHubOrientationOnRobot(HUB_LOGO, HUB_USB)));
            imu.resetYaw();
        }

        // Odometry. Position 0, 0 and heading 0 are where the robot stands when INIT is pressed:
        // X counts inches forward from there, Y inches to the left. Keep the robot still during INIT.
        pinpoint = hardwareMap.tryGet(GoBildaPinpointDriver.class, PINPOINT_NAME);
        if (pinpoint != null) {
            pinpoint.setOffsets(X_POD_OFFSET_MM, Y_POD_OFFSET_MM, DistanceUnit.MM);
            pinpoint.setEncoderResolution(GoBildaPinpointDriver.GoBildaOdometryPods.goBILDA_4_BAR_POD);
            pinpoint.setEncoderDirections(X_POD_DIRECTION, Y_POD_DIRECTION);
            pinpoint.resetPosAndIMU();
        }

        telemetry.addData("Status", "Ready. Press start.");
        telemetry.addData("Levers", "start folded IN. They move when you press start.");
    }

    @Override
    public void loop() {
        // ---- driving ----
        double forward = -gamepad1.left_stick_y;   // stick forward is negative
        double strafe = gamepad1.left_stick_x;
        double turn = gamepad1.right_stick_x;
        double heading = imu == null ? 0.0 : imu.getRobotYawPitchRollAngles().getYaw(AngleUnit.RADIANS);

        if (gamepad1.y && !lastY) fieldCentric = !fieldCentric;
        lastY = gamepad1.y;
        if (gamepad1.x && imu != null) imu.resetYaw();
        if (fieldCentric && imu != null) {
            // Turn "away from the driver" on the stick into the robot's own forward / sideways.
            // heading is counter-clockwise (left turn = positive), as the IMU reports it.
            double f = forward * Math.cos(heading) - strafe * Math.sin(heading);
            double s = forward * Math.sin(heading) + strafe * Math.cos(heading);
            forward = f;
            strafe = s;
        }
        double scale = gamepad1.left_bumper ? SLOW_SCALE : 1.0;
        // Mecanum mix. Dividing by the biggest total keeps every power between -1 and 1.
        double biggest = Math.max(Math.abs(forward) + Math.abs(strafe) + Math.abs(turn), 1.0);
        frontLeft.setPower((forward + strafe + turn) / biggest * scale);
        frontRight.setPower((forward - strafe - turn) / biggest * scale);
        backLeft.setPower((forward - strafe + turn) / biggest * scale);
        backRight.setPower((forward + strafe - turn) / biggest * scale);

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

        // ---- levers: each press flips one between in and out ----
        if (gamepad1.a && !lastA) leverFrontOut = !leverFrontOut;
        if (gamepad1.b && !lastB) leverBackOut = !leverBackOut;
        lastA = gamepad1.a;
        lastB = gamepad1.b;
        setLever(leverFront, leverFrontOut ? LEVER_FRONT_OUT : LEVER_FRONT_IN);
        setLever(leverBack, leverBackOut ? LEVER_BACK_OUT : LEVER_BACK_IN);

        // ---- Driver Station ----
        telemetry.addData("Drive", (fieldCentric && imu != null ? "field-centric" : "robot-centric") + (gamepad1.left_bumper ? "  SLOW" : ""));
        telemetry.addData("Heading", "%.1f deg", Math.toDegrees(heading));
        telemetry.addData("Front lever (A)", (leverFrontOut ? "OUT" : "in") + missingNote(leverFront, "leverFrontLeft", "leverFrontRight"));
        telemetry.addData("Back lever (B)", (leverBackOut ? "OUT" : "in") + missingNote(leverBack, "leverBackLeft", "leverBackRight"));
        if (pinpoint == null) {
            telemetry.addData("Odometry", "\"" + PINPOINT_NAME + "\" NOT in the configuration");
        } else {
            telemetry.addData("Position", "x %.1f in  y %.1f in  facing %.1f deg", odoX, odoY, odoHeading);
            telemetry.addData("Speed", "%.1f in/s  (odometry %s)", speedInPerS, pinpoint.getDeviceStatus());
        }
        if (imu == null) telemetry.addData("IMU", "\"imu\" NOT in the configuration: robot-centric only");
    }

    /** One of a lever's two servos, or null when it is not in the configuration. */
    private Servo leverServo(String name, boolean reversed) {
        Servo s = hardwareMap.tryGet(Servo.class, name);
        if (s != null) s.setDirection(reversed ? Servo.Direction.REVERSE : Servo.Direction.FORWARD);
        return s;
    }

    /** Send both servos of a lever to the same position. */
    private static void setLever(Servo[] pair, double position) {
        for (Servo s : pair) if (s != null) s.setPosition(position);
    }

    private static String missingNote(Servo[] pair, String left, String right) {
        String note = "";
        if (pair[0] == null) note += "   " + left + " NOT in the configuration";
        if (pair[1] == null) note += "   " + right + " NOT in the configuration";
        return note;
    }
}
