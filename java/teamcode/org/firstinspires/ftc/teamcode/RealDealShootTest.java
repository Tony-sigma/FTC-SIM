package org.firstinspires.ftc.teamcode;

import com.qualcomm.robotcore.eventloop.opmode.OpMode;
import com.qualcomm.robotcore.eventloop.opmode.TeleOp;
import com.qualcomm.robotcore.hardware.DcMotor;
import com.qualcomm.robotcore.hardware.DcMotorEx;
import com.qualcomm.robotcore.hardware.DcMotorSimple;

/**
 * The real deal shoot test: the shooter only, speed in steps of 1000 rpm.
 *
 *   RIGHT TRIGGER (each full press)   +1000 rpm, up to 6000 (the last steps are simply full power)
 *   LEFT TRIGGER  (each full press)   -1000 rpm
 *   B                                 STOP (back to 0)
 *   Hold RIGHT BUMPER                 feeders forward   (only if they are in the configuration)
 *   Hold LEFT BUMPER                  feeders backwards
 *
 * It starts at 0: nothing turns until the first press. The speed is measured with one encoder and both
 * motors get the same power, so they cannot fight each other.
 *
 * Stay BEHIND the robot, safety glasses on. The small top wheels turn 2.25 times faster than the number
 * on the screen.
 */
@TeleOp(name = "Real Deal Shoot Test", group = "Tests")
public class RealDealShootTest extends OpMode {
    static final double STEP_RPM = 1000.0;
    static final double TOP_RPM = 6000.0;
    // As found on the real robot: left reversed, right not.
    static final boolean REVERSE_SHOOTER_LEFT = true;
    static final boolean REVERSE_SHOOTER_RIGHT = false;
    static final boolean REVERSE_INTAKE_A = false;
    static final boolean REVERSE_INTAKE_B = false;
    /** Whose encoder measures the speed: true = shooterLeft, false = shooterRight. */
    static final boolean SPEED_FROM_LEFT = true;
    static final double TICKS_PER_REV = 28.0;
    /** About the speed the wheels reach at full power. Asking for more than this just gives full power. */
    static final double MAX_RPM = 5000.0;
    static final double KP = 5.0, KI = 2.0;

    private DcMotorEx shooterLeft, shooterRight, intakeA, intakeB;
    private double targetRpm = 0.0, speedSum = 0.0, speedSeenAt = 0.0, lastLoopTime = 0.0;
    private boolean speedBlind = false, rightWasDown = false, leftWasDown = false;

    @Override
    public void init() {
        shooterLeft = motor("shooterLeft", REVERSE_SHOOTER_LEFT);
        shooterRight = motor("shooterRight", REVERSE_SHOOTER_RIGHT);
        intakeA = motor("intakeA", REVERSE_INTAKE_A);
        intakeB = motor("intakeB", REVERSE_INTAKE_B);
        telemetry.addLine("Right trigger = +1000 rpm, left trigger = -1000, B = stop.");
        telemetry.addLine("Stay behind the robot. Safety glasses on.");
    }

    @Override
    public void loop() {
        double now = getRuntime();
        double dt = Math.max(0.001, Math.min(0.1, now - lastLoopTime));
        lastLoopTime = now;

        // One step for each full press of a trigger (it has to be let go before it counts again).
        boolean rightDown = gamepad1.right_trigger > (rightWasDown ? 0.2 : 0.7);
        boolean leftDown = gamepad1.left_trigger > (leftWasDown ? 0.2 : 0.7);
        if (rightDown && !rightWasDown) targetRpm += STEP_RPM;
        if (leftDown && !leftWasDown) targetRpm -= STEP_RPM;
        rightWasDown = rightDown;
        leftWasDown = leftDown;
        if (gamepad1.b) targetRpm = 0.0;
        targetRpm = Math.max(0.0, Math.min(TOP_RPM, targetRpm));

        double leftRpm = shooterLeft == null ? 0.0 : shooterLeft.getVelocity() / TICKS_PER_REV * 60.0;
        double rightRpm = shooterRight == null ? 0.0 : shooterRight.getVelocity() / TICKS_PER_REV * 60.0;
        double measured = Math.abs(SPEED_FROM_LEFT ? leftRpm : rightRpm);

        // Power: a first guess from the speed wanted, corrected by how far short the wheel is.
        double power = 0.0;
        if (targetRpm <= 0.0) {
            speedSum = 0.0;
            speedBlind = false;
            speedSeenAt = now;
        } else {
            double base = Math.min(1.0, targetRpm / MAX_RPM);
            if (measured > 0.1 * targetRpm) speedSeenAt = now;
            if (now - speedSeenAt > 0.7) speedBlind = true;   // no reading: stop trusting the encoder
            if (speedBlind) {
                power = base;
            } else {
                double shortfall = (targetRpm - measured) / MAX_RPM;
                if (Math.abs(shortfall) < 0.03) speedSum = Math.max(-0.15, Math.min(0.15, speedSum + shortfall * dt));
                power = Math.max(0.0, Math.min(1.0, base + KP * shortfall + KI * speedSum));
            }
        }
        if (shooterLeft != null) shooterLeft.setPower(power);
        if (shooterRight != null) shooterRight.setPower(power);

        double feed = gamepad1.right_bumper ? 1.0 : gamepad1.left_bumper ? -1.0 : 0.0;
        if (intakeA != null) intakeA.setPower(feed);
        if (intakeB != null) intakeB.setPower(feed);

        telemetry.addData("Target", "%.0f rpm   (right trigger +1000, left trigger -1000, B stop)", targetRpm);
        telemetry.addData("Power", "%.0f %%", power * 100.0);
        telemetry.addData("shooterLeft", shooterLeft == null ? "NOT in the configuration" : String.format("%+.0f rpm", leftRpm));
        telemetry.addData("shooterRight", shooterRight == null ? "NOT in the configuration" : String.format("%+.0f rpm", rightRpm));
        if (speedBlind) telemetry.addLine("NO SPEED READING (jam, or encoder cable): running on plain power. Press B, then go again.");
        else if (Math.abs(leftRpm) > 300 && Math.abs(rightRpm) > 300 && Math.abs(Math.abs(leftRpm) - Math.abs(rightRpm)) > 0.15 * Math.abs(leftRpm))
            telemetry.addLine("THE TWO MOTORS SHOW DIFFERENT SPEEDS: something between them slips, or an encoder is faulty.");
    }

    @Override
    public void stop() {
        if (shooterLeft != null) shooterLeft.setPower(0.0);
        if (shooterRight != null) shooterRight.setPower(0.0);
    }

    private DcMotorEx motor(String name, boolean reversed) {
        DcMotorEx m = hardwareMap.tryGet(DcMotorEx.class, name);
        if (m == null) return null;
        m.setDirection(reversed ? DcMotorSimple.Direction.REVERSE : DcMotorSimple.Direction.FORWARD);
        m.setMode(DcMotor.RunMode.RUN_WITHOUT_ENCODER);
        m.setZeroPowerBehavior(DcMotor.ZeroPowerBehavior.FLOAT);
        return m;
    }
}
