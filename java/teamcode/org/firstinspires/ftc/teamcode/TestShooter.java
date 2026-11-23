package org.firstinspires.ftc.teamcode;

import com.qualcomm.robotcore.eventloop.opmode.OpMode;
import com.qualcomm.robotcore.eventloop.opmode.TeleOp;
import com.qualcomm.robotcore.hardware.DcMotor;
import com.qualcomm.robotcore.hardware.DcMotorEx;

/**
 * TEST: only the shooter flywheel (the hood has its own test). Start slow! These motors are fast: 0.20 is already a real shot.
 *
 *   D-pad UP / DOWN   raise / lower the power by 0.02 (it starts at 0.10)
 *   A                 flywheel ON
 *   B                 flywheel OFF
 *
 * The screen shows each motor's speed. Use it to:
 *   - check both motors turn and reach about the same speed (if one fights the other, flip REVERSED);
 *   - write down the power and rpm that reach the hive from each distance;
 *   - watch how far the rpm dips when a pollen goes through (that tells us the real "speed drop").
 * Power is capped at MAX_POWER so a slip of the thumb cannot send it to full speed.
 */
@TeleOp(name = "Test: Shooter", group = "Tests")
public class TestShooter extends OpMode {
    static final String[] NAMES = {"shooterLeft", "shooterRight"};
    static final boolean[] REVERSED = {false, false};
    static final double MAX_POWER = 0.40;
    static final double TICKS_PER_REV = 28.0;   // bare goBILDA motor (gearbox removed)

    private final DcMotorEx[] motors = new DcMotorEx[2];
    private double power = 0.10;
    private boolean running = false;
    private boolean lastUp, lastDown;

    @Override
    public void init() {
        for (int i = 0; i < 2; i++) {
            motors[i] = hardwareMap.tryGet(DcMotorEx.class, NAMES[i]);
            if (motors[i] != null) {
                motors[i].setMode(DcMotor.RunMode.RUN_WITHOUT_ENCODER);
                motors[i].setZeroPowerBehavior(DcMotor.ZeroPowerBehavior.FLOAT);
            }
        }
        telemetry.addLine("Nobody in front of the shooter? Press start, then A.");
    }

    @Override
    public void loop() {
        if (gamepad1.dpad_up && !lastUp) power += 0.02;
        if (gamepad1.dpad_down && !lastDown) power -= 0.02;
        lastUp = gamepad1.dpad_up;
        lastDown = gamepad1.dpad_down;
        power = Math.max(0.0, Math.min(MAX_POWER, power));
        if (gamepad1.a) running = true;
        if (gamepad1.b) running = false;

        telemetry.addLine("A on   B off   D-pad U/D power");
        telemetry.addData("Flywheel", running ? "ON" : "off");
        telemetry.addData("Power", "%.2f  (max %.2f)", power, MAX_POWER);
        for (int i = 0; i < 2; i++) {
            if (motors[i] == null) {
                telemetry.addData(NAMES[i], "NOT FOUND in the configuration");
                continue;
            }
            motors[i].setPower(running ? power * (REVERSED[i] ? -1.0 : 1.0) : 0.0);
            double rpm = Math.abs(motors[i].getVelocity()) / TICKS_PER_REV * 60.0;
            telemetry.addData(NAMES[i], "%.0f rpm", rpm);
        }
    }

    @Override
    public void stop() {
        for (DcMotorEx m : motors) if (m != null) m.setPower(0.0);
    }
}
