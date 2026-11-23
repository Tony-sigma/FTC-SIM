package org.firstinspires.ftc.teamcode;

import com.qualcomm.robotcore.eventloop.opmode.OpMode;
import com.qualcomm.robotcore.eventloop.opmode.TeleOp;
import com.qualcomm.robotcore.hardware.Servo;

/**
 * TEST: only the turret.
 *
 *   A                    ARM: the turret moves to the position shown (it starts at 0.50, the middle)
 *   D-pad LEFT / RIGHT   turn slowly (hold)
 *   LEFT / RIGHT BUMPER  jump 0.05
 *   Y                    back to the middle (0.50)
 *   B                    disarm (stop sending positions)
 *
 * Nothing moves until you press A. Turn in small steps and stop as soon as the turret reaches the end
 * of its travel or a wire goes tight. Write down the smallest and largest position that are safe:
 * those are the turret's limits for the real TeleOp. If LEFT on the D-pad turns it right, set
 * LEFT_IS_BIGGER to false.
 */
@TeleOp(name = "Test: Turret", group = "Tests")
public class TestTurret extends OpMode {
    static final String NAME = "turretServo";
    static final boolean LEFT_IS_BIGGER = true;
    static final double NUDGE_PER_LOOP = 0.002;
    // Only used for the angle shown on screen: servo travel through the 15-tooth : 70-tooth gears.
    static final double SERVO_TRAVEL_DEG = 300.0;
    static final double GEAR_RATIO = 15.0 / 70.0;

    private Servo servo;
    private double position = 0.5;
    private boolean armed = false;
    private boolean lastLb, lastRb;

    @Override
    public void init() {
        servo = hardwareMap.tryGet(Servo.class, NAME);
        telemetry.addLine(servo == null ? NAME + " NOT FOUND in the configuration" : "Turret stays still until you press A.");
    }

    @Override
    public void loop() {
        double left = LEFT_IS_BIGGER ? 1.0 : -1.0;
        if (gamepad1.dpad_left) position += NUDGE_PER_LOOP * left;
        if (gamepad1.dpad_right) position -= NUDGE_PER_LOOP * left;
        if (gamepad1.left_bumper && !lastLb) position += 0.05 * left;
        if (gamepad1.right_bumper && !lastRb) position -= 0.05 * left;
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
        telemetry.addLine("A arm   D-pad L/R turn   bumpers jump   Y middle   B disarm");
        telemetry.addData("Turret", armed ? "MOVING to the position below" : "not armed (press A)");
        telemetry.addData("Position", "%.3f", position);
        telemetry.addData("About", "%.1f deg from the middle", (position - 0.5) * SERVO_TRAVEL_DEG * GEAR_RATIO);
    }
}
