package org.firstinspires.ftc.teamcode;

import com.qualcomm.hardware.rev.RevHubOrientationOnRobot;
import com.qualcomm.robotcore.eventloop.opmode.OpMode;
import com.qualcomm.robotcore.eventloop.opmode.TeleOp;
import com.qualcomm.robotcore.hardware.DcMotor;
import com.qualcomm.robotcore.hardware.DcMotorSimple;
import com.qualcomm.robotcore.hardware.IMU;
import com.qualcomm.robotcore.hardware.Servo;
import org.firstinspires.ftc.robotcore.external.navigation.AngleUnit;

/**
 * Only the chassis and the two lever servos. Nothing else on the robot is touched.
 *
 *   Left stick   drive / strafe          Right stick   turn
 *   Left bumper  slow mode (hold)
 *   A            front lever out / in    B             back lever out / in
 *   Y            field-centric on / off  X             reset heading (robot facing away from you)
 *
 * Names needed in the robot configuration:
 *   motors  frontLeft, frontRight, backLeft, backRight
 *   servos  leverLeft (front lever), leverRight (back lever)
 *   the Control Hub's built-in IMU, called "imu" (only needed for field-centric driving)
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

    // Lever servo positions (find them with "Test: Levers"): folded in, and out working a flower.
    // The two servos are mirrored, so on the real robot one of them probably needs its numbers swapped.
    static final double LEVER_FRONT_IN = 0.0, LEVER_FRONT_OUT = 1.0;
    static final double LEVER_BACK_IN = 0.0, LEVER_BACK_OUT = 1.0;

    // ==================================================================================

    private DcMotor frontLeft, frontRight, backLeft, backRight;
    private Servo leverFront, leverBack;
    private IMU imu;

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
        leverFront = hardwareMap.tryGet(Servo.class, "leverLeft");
        leverBack = hardwareMap.tryGet(Servo.class, "leverRight");
        imu = hardwareMap.tryGet(IMU.class, "imu");
        if (imu != null) {
            imu.initialize(new IMU.Parameters(new RevHubOrientationOnRobot(HUB_LOGO, HUB_USB)));
            imu.resetYaw();
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

        // ---- levers: each press flips one between in and out ----
        if (gamepad1.a && !lastA) leverFrontOut = !leverFrontOut;
        if (gamepad1.b && !lastB) leverBackOut = !leverBackOut;
        lastA = gamepad1.a;
        lastB = gamepad1.b;
        if (leverFront != null) leverFront.setPosition(leverFrontOut ? LEVER_FRONT_OUT : LEVER_FRONT_IN);
        if (leverBack != null) leverBack.setPosition(leverBackOut ? LEVER_BACK_OUT : LEVER_BACK_IN);

        // ---- Driver Station ----
        telemetry.addData("Drive", (fieldCentric && imu != null ? "field-centric" : "robot-centric") + (gamepad1.left_bumper ? "  SLOW" : ""));
        telemetry.addData("Heading", "%.1f deg", Math.toDegrees(heading));
        telemetry.addData("Front lever (A)", leverFront == null ? "leverLeft NOT in the configuration" : leverFrontOut ? "OUT" : "in");
        telemetry.addData("Back lever (B)", leverBack == null ? "leverRight NOT in the configuration" : leverBackOut ? "OUT" : "in");
        if (imu == null) telemetry.addData("IMU", "\"imu\" NOT in the configuration: robot-centric only");
    }
}
