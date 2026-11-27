package org.firstinspires.ftc.teamcode;

import com.qualcomm.robotcore.eventloop.opmode.OpMode;
import com.qualcomm.robotcore.eventloop.opmode.TeleOp;
import com.qualcomm.robotcore.hardware.Servo;

/**
 * TEST: only the levers.
 *
 *   X                 work on the FRONT lever      B   work on the BACK lever
 *   A                 ARM the chosen lever: it moves to the position shown (starts at 0.50)
 *   D-pad UP / DOWN   move slowly (hold)
 *   BUMPERS           right +0.05, left -0.05
 *   Y                 disarm both (stop sending positions)
 *
 * Nothing moves until you choose a lever and press A. For each lever find and write down two numbers:
 * its resting position and its fully-out position (the one that wedges under the flower). Stop the
 * moment the lever touches the frame or the floor.
 *
 * Each lever has TWO servos, one at each end of its bar, facing each other. One of each pair must be
 * reversed (the REVERSED list below) or the two push against each other: they buzz, get hot and can
 * burn out. So the FIRST time, check each servo ALONE:
 *   1. Unplug one servo of the pair from the hub (an unplugged servo turns freely).
 *   2. Arm the lever and press D-pad UP: note which way the lever swings.
 *   3. Swap: plug that one back in, unplug the other, and do the same.
 *   4. Both must swing the SAME way on D-pad UP. If they do not, change true/false for one of them
 *      in REVERSED. Only then plug both in.
 * Copy the REVERSED values and the two positions you found into the TeleOps.
 */
@TeleOp(name = "Test: Levers", group = "Tests")
public class TestLevers extends OpMode {
    static final String[][] NAMES = {{"leverFrontLeft", "leverFrontRight"}, {"leverBackLeft", "leverBackRight"}};
    static final boolean[][] REVERSED = {{false, true}, {false, true}};
    static final String[] LABELS = {"FRONT lever", "BACK lever"};
    static final double NUDGE_PER_LOOP = 0.002;

    private final Servo[][] servos = new Servo[2][];
    private final double[] positions = {0.5, 0.5};
    private final boolean[] armed = {false, false};
    private int selected = 0;
    private boolean lastLb, lastRb;

    @Override
    public void init() {
        for (int lever = 0; lever < 2; lever++) {
            servos[lever] = new Servo[NAMES[lever].length];
            for (int i = 0; i < NAMES[lever].length; i++) {
                servos[lever][i] = hardwareMap.tryGet(Servo.class, NAMES[lever][i]);
                if (servos[lever][i] != null && REVERSED[lever][i]) servos[lever][i].setDirection(Servo.Direction.REVERSE);
            }
        }
        telemetry.addLine("Levers stay still until you choose one (X or B) and press A.");
    }

    @Override
    public void loop() {
        if (gamepad1.x) selected = 0;
        if (gamepad1.b) selected = 1;
        if (gamepad1.a) armed[selected] = true;
        if (gamepad1.y) { armed[0] = false; armed[1] = false; }
        if (gamepad1.dpad_up) positions[selected] += NUDGE_PER_LOOP;
        if (gamepad1.dpad_down) positions[selected] -= NUDGE_PER_LOOP;
        if (gamepad1.right_bumper && !lastRb) positions[selected] += 0.05;
        if (gamepad1.left_bumper && !lastLb) positions[selected] -= 0.05;
        lastLb = gamepad1.left_bumper;
        lastRb = gamepad1.right_bumper;
        positions[selected] = Math.max(0.0, Math.min(1.0, positions[selected]));

        telemetry.addLine("X front   B back   A arm   D-pad U/D move   bumpers jump   Y disarm both");
        for (int lever = 0; lever < 2; lever++) {
            boolean found = false;
            for (int i = 0; i < servos[lever].length; i++) {
                if (servos[lever][i] == null) {
                    telemetry.addData(NAMES[lever][i], "NOT FOUND in the configuration");
                } else {
                    found = true;
                    if (armed[lever]) servos[lever][i].setPosition(positions[lever]);
                }
            }
            String mark = lever == selected ? ">> " : "   ";
            if (found) telemetry.addData(mark + LABELS[lever], "%.3f   %s", positions[lever], armed[lever] ? "MOVING" : "not armed");
        }
    }
}
