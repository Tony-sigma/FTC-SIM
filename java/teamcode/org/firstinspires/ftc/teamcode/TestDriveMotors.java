package org.firstinspires.ftc.teamcode;

import com.qualcomm.robotcore.eventloop.opmode.OpMode;
import com.qualcomm.robotcore.eventloop.opmode.TeleOp;
import com.qualcomm.robotcore.hardware.DcMotor;
import com.qualcomm.robotcore.hardware.DcMotorSimple;

/**
 * TEST: one drive motor at a time. Put the robot on blocks so the wheels are off the ground!
 *
 *   Hold X = frontLeft     Hold Y = frontRight
 *   Hold A = backLeft      Hold B = backRight
 *   Hold LEFT BUMPER as well to run it backwards.
 *
 * Every wheel should turn the way that would drive the robot FORWARD, and its encoder number should
 * go UP. If a wheel turns backwards, change its direction in the DIRECTIONS list below (and use the
 * same directions in your real TeleOp). If the wrong wheel turns, the motor is in the wrong port or
 * has the wrong name in the configuration.
 */
@TeleOp(name = "Test 1: Drive Motors", group = "Tests")
public class TestDriveMotors extends OpMode {
    static final String[] NAMES = {"frontLeft", "frontRight", "backLeft", "backRight"};
    static final DcMotorSimple.Direction[] DIRECTIONS = {
        DcMotorSimple.Direction.REVERSE, DcMotorSimple.Direction.FORWARD,
        DcMotorSimple.Direction.REVERSE, DcMotorSimple.Direction.FORWARD};
    static final double TEST_POWER = 0.3;

    private final DcMotor[] motors = new DcMotor[4];

    @Override
    public void init() {
        for (int i = 0; i < 4; i++) {
            motors[i] = hardwareMap.tryGet(DcMotor.class, NAMES[i]);
            if (motors[i] != null) {
                motors[i].setDirection(DIRECTIONS[i]);
                motors[i].setMode(DcMotor.RunMode.STOP_AND_RESET_ENCODER);
                motors[i].setMode(DcMotor.RunMode.RUN_WITHOUT_ENCODER);
                motors[i].setZeroPowerBehavior(DcMotor.ZeroPowerBehavior.BRAKE);
            }
        }
        telemetry.addLine("Wheels OFF the ground? Then press start.");
    }

    @Override
    public void loop() {
        boolean[] held = {gamepad1.x, gamepad1.y, gamepad1.a, gamepad1.b};
        double power = gamepad1.left_bumper ? -TEST_POWER : TEST_POWER;
        telemetry.addLine("X frontLeft   Y frontRight   A backLeft   B backRight   (LB = backwards)");
        for (int i = 0; i < 4; i++) {
            if (motors[i] == null) {
                telemetry.addData(NAMES[i], "NOT FOUND in the configuration");
                continue;
            }
            motors[i].setPower(held[i] ? power : 0.0);
            telemetry.addData(NAMES[i], "%s   encoder %d", held[i] ? "RUNNING" : "stopped", motors[i].getCurrentPosition());
        }
    }
}
