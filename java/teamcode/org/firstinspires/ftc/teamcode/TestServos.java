package org.firstinspires.ftc.teamcode;

import com.qualcomm.robotcore.eventloop.opmode.OpMode;
import com.qualcomm.robotcore.eventloop.opmode.TeleOp;
import com.qualcomm.robotcore.hardware.Servo;

/**
 * TEST: move one servo at a time and read off its position, to find each mechanism's safe limits.
 * Use it for the turret, the hood, the gate and the levers.
 *
 *   D-pad LEFT / RIGHT   choose the servo (the one you leave stops being commanded)
 *   A                    ARM the chosen servo: it moves to the position shown
 *   D-pad UP / DOWN      nudge the position slowly (hold)
 *   RIGHT / LEFT BUMPER  jump +0.05 / -0.05
 *   Y                    go to 0.50 (the middle)
 *   B                    disarm (stop sending positions)
 *
 * A servo does nothing until you press A, so nothing jumps when you press start. Move in small steps,
 * stop as soon as the mechanism reaches its end, and write down the number: never push past it, a
 * stalled servo burns out. Add or remove names in the list below to match your robot.
 */
@TeleOp(name = "Test: Any Servo", group = "Tests")
public class TestServos extends OpMode {
    static final String[] NAMES = {"turretServo", "hoodServo", "gateServo", "leverFrontLeft", "leverFrontRight", "leverBackLeft", "leverBackRight"};
    static final double NUDGE_PER_LOOP = 0.002;

    private final Servo[] servos = new Servo[NAMES.length];
    private final double[] positions = new double[NAMES.length];
    private int selected = 0;
    private boolean armed = false;
    private boolean lastLeft, lastRight, lastA, lastB, lastY, lastLb, lastRb;

    @Override
    public void init() {
        for (int i = 0; i < NAMES.length; i++) {
            servos[i] = hardwareMap.tryGet(Servo.class, NAMES[i]);
            positions[i] = 0.5;
        }
        telemetry.addLine("Servos stay still until you choose one and press A.");
    }

    @Override
    public void loop() {
        if (gamepad1.dpad_right && !lastRight) { selected = (selected + 1) % NAMES.length; armed = false; }
        if (gamepad1.dpad_left && !lastLeft) { selected = (selected + NAMES.length - 1) % NAMES.length; armed = false; }
        if (gamepad1.a && !lastA) armed = true;
        if (gamepad1.b && !lastB) armed = false;
        if (gamepad1.y && !lastY) positions[selected] = 0.5;
        if (gamepad1.right_bumper && !lastRb) positions[selected] += 0.05;
        if (gamepad1.left_bumper && !lastLb) positions[selected] -= 0.05;
        if (gamepad1.dpad_up) positions[selected] += NUDGE_PER_LOOP;
        if (gamepad1.dpad_down) positions[selected] -= NUDGE_PER_LOOP;
        positions[selected] = Math.max(0.0, Math.min(1.0, positions[selected]));
        lastRight = gamepad1.dpad_right; lastLeft = gamepad1.dpad_left;
        lastA = gamepad1.a; lastB = gamepad1.b; lastY = gamepad1.y;
        lastRb = gamepad1.right_bumper; lastLb = gamepad1.left_bumper;

        Servo servo = servos[selected];
        if (servo != null && armed) servo.setPosition(positions[selected]);

        telemetry.addLine("D-pad L/R choose   A arm   D-pad U/D nudge   bumpers +-0.05   Y middle   B disarm");
        for (int i = 0; i < NAMES.length; i++) {
            String mark = i == selected ? (armed ? ">> MOVING " : ">> chosen ") : "   ";
            telemetry.addData(mark + NAMES[i], servos[i] == null ? "NOT FOUND in the configuration" : String.format("%.3f", positions[i]));
        }
    }
}
