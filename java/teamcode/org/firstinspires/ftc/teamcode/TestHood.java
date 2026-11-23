package org.firstinspires.ftc.teamcode;

import com.qualcomm.robotcore.eventloop.opmode.OpMode;
import com.qualcomm.robotcore.eventloop.opmode.TeleOp;
import com.qualcomm.robotcore.hardware.Servo;

/**
 * TEST: only the hood (the arm that carries the shooter's top wheel).
 *
 *   A                 ARM: the hood moves to the position shown (it starts at 0.50)
 *   D-pad UP / DOWN   move slowly (hold)
 *   BUMPERS           right +0.05, left -0.05
 *   Y                 back to 0.50
 *   B                 disarm (stop sending positions)
 *
 * Nothing moves until you press A. Go in small steps to each end of the hood's travel and stop the
 * moment it touches its end stop. Write down both numbers: one is the steepest shot, the other the
 * flattest. The flywheel stays off in this test.
 */
@TeleOp(name = "Test: Hood", group = "Tests")
public class TestHood extends OpMode {
    static final String NAME = "hoodServo";
    static final double NUDGE_PER_LOOP = 0.002;

    private Servo servo;
    private double position = 0.5;
    private boolean armed = false;
    private boolean lastLb, lastRb;

    @Override
    public void init() {
        servo = hardwareMap.tryGet(Servo.class, NAME);
        telemetry.addLine(servo == null ? NAME + " NOT FOUND in the configuration" : "Hood stays still until you press A.");
    }

    @Override
    public void loop() {
        if (gamepad1.dpad_up) position += NUDGE_PER_LOOP;
        if (gamepad1.dpad_down) position -= NUDGE_PER_LOOP;
        if (gamepad1.right_bumper && !lastRb) position += 0.05;
        if (gamepad1.left_bumper && !lastLb) position -= 0.05;
        lastLb = gamepad1.left_bumper;
        lastRb = gamepad1.right_bumper;
        if (gamepad1.y) position = 0.5;
        if (gamepad1.a) armed = true;
        if (gamepad1.b) armed = false;
        position = Math.max(0.0, Math.min(1.0, position));

        if (servo == null) {
            telemetry.addData(NAME, "NOT FOUND in the configuration");
            return;
        }
        if (armed) servo.setPosition(position);
        telemetry.addLine("A arm   D-pad U/D move   bumpers jump   Y 0.50   B disarm");
        telemetry.addData("Hood", armed ? "MOVING to the position below" : "not armed (press A)");
        telemetry.addData("Position", "%.3f", position);
    }
}
