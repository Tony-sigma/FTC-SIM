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
 * Sample driver-controlled OpMode. It is ordinary FTC code: the same file runs on the Control Hub
 * and in the simulator.
 *
 *   Left stick   drive / strafe          Right stick  turn
 *   Left trigger intake (both sides)     Right trigger shoot
 *   Right bumper spit pollen back out    Left bumper   slow mode
 *   D-pad left/right  turret             D-pad up/down hood
 *   A / B        front / back lever      Y  field-centric on/off     X  reset heading
 */
@TeleOp(name = "Biobuzz TeleOp", group = "Biobuzz")
public class BiobuzzTeleOp extends OpMode {
    private DcMotor frontLeft, frontRight, backLeft, backRight;
    private DcMotor intakeA, intakeB, shooterLeft, shooterRight;
    private Servo turretServo, hoodServo, gateServo, leverLeft, leverRight;
    private IMU imu;

    private double turret = 0.5, hood = 0.5;
    private boolean fieldCentric = false, leverFrontOut = false, leverBackOut = false;
    private boolean lastA, lastB, lastY;

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
        shooterLeft.setPower(1.0);                    // flywheel always spinning
        shooterRight.setPower(1.0);
        gateServo.setPosition(shoot ? 1.0 : 0.0);     // the gate lets pollen through only while shooting

        // ---- turret, hood, levers ----
        if (gamepad1.dpad_left) turret += 0.004;
        if (gamepad1.dpad_right) turret -= 0.004;
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
        telemetry.addData("Front left encoder", frontLeft.getCurrentPosition());
    }
}
