package org.firstinspires.ftc.teamcode;

import com.qualcomm.robotcore.eventloop.opmode.OpMode;
import com.qualcomm.robotcore.eventloop.opmode.TeleOp;
import com.qualcomm.robotcore.hardware.DcMotor;

/**
 * TEST: only the intakes and feeders. Each intake shares one motor with its feeder, so there are two
 * motors, one on each trigger.
 *
 *   RIGHT TRIGGER  intakeA (front)   - the harder you squeeze, the faster
 *   LEFT TRIGGER   intakeB (back)
 *   Hold RIGHT BUMPER to run them in reverse.
 *
 * Each one should pull pollen IN and carry it up towards the shooter. If one pushes pollen out, flip
 * its sign in REVERSED below (and reverse that motor in your real TeleOp).
 */
@TeleOp(name = "Test: Intake + Feeder", group = "Tests")
public class TestIntakes extends OpMode {
    static final String[] NAMES = {"intakeA", "intakeB"};
    static final boolean[] REVERSED = {false, false};
    static final double MAX_POWER = 1.0;

    private final DcMotor[] motors = new DcMotor[2];

    @Override
    public void init() {
        for (int i = 0; i < 2; i++) motors[i] = hardwareMap.tryGet(DcMotor.class, NAMES[i]);
        telemetry.addLine("Keep fingers out of the intakes. Press start.");
    }

    @Override
    public void loop() {
        double[] triggers = {gamepad1.right_trigger, gamepad1.left_trigger};
        double sign = gamepad1.right_bumper ? -1.0 : 1.0;
        telemetry.addLine("RT intakeA   LT intakeB   (hold RB = reverse)");
        for (int i = 0; i < 2; i++) {
            if (motors[i] == null) {
                telemetry.addData(NAMES[i], "NOT FOUND in the configuration");
                continue;
            }
            double power = triggers[i] * MAX_POWER * sign * (REVERSED[i] ? -1.0 : 1.0);
            motors[i].setPower(power);
            telemetry.addData(NAMES[i], "power %.2f", power);
        }
    }
}
