package org.firstinspires.ftc.teamcode;

import com.qualcomm.robotcore.eventloop.opmode.OpMode;
import com.qualcomm.robotcore.eventloop.opmode.TeleOp;
import com.qualcomm.robotcore.hardware.DcMotor;
import com.qualcomm.robotcore.hardware.DcMotorEx;
import com.qualcomm.robotcore.hardware.DcMotorSimple;

/**
 * TEST: the shooter at full power, nothing clever. No speed control, no camera, no servos.
 *
 *   HOLD the right trigger   both shooter motors at POWER (below). Let go and they are off.
 *   HOLD the left trigger    feeders forward (if they are in the configuration)
 *   HOLD the right bumper    feeders backwards
 *
 * DANGER, read this first. POWER = 1.0 is everything the motors have. The small top wheels are geared
 * 2.25 times faster than the big ones, so they and their printed pulleys may reach 10000 rpm or more,
 * and a ball that gets through leaves very fast. Parts can come off. So:
 *   - everybody behind the robot, nobody in front or level with the wheels, safety glasses on;
 *   - point it at a wall or a hanging blanket;
 *   - hold the trigger only for as long as you need to see what happens, then let go.
 * To try less first, change POWER to 0.5.
 */
@TeleOp(name = "Test: Shooter FULL POWER", group = "Tests")
public class TestShooterFullPower extends OpMode {
    /** 1.0 = full power. */
    static final double POWER = 1.0;
    // As found on the real robot: left reversed, right not.
    static final boolean REVERSE_SHOOTER_LEFT = true;
    static final boolean REVERSE_SHOOTER_RIGHT = false;
    static final boolean REVERSE_INTAKE_A = false;
    static final boolean REVERSE_INTAKE_B = false;
    static final double TICKS_PER_REV = 28.0;

    private DcMotorEx shooterLeft, shooterRight, intakeA, intakeB;

    @Override
    public void init() {
        shooterLeft = motor("shooterLeft", REVERSE_SHOOTER_LEFT);
        shooterRight = motor("shooterRight", REVERSE_SHOOTER_RIGHT);
        intakeA = motor("intakeA", REVERSE_INTAKE_A);
        intakeB = motor("intakeB", REVERSE_INTAKE_B);
        telemetry.addLine("HOLD the right trigger = shooter at full power. Let go = off.");
        telemetry.addLine("Everybody behind the robot. Safety glasses on.");
    }

    @Override
    public void loop() {
        double shoot = gamepad1.right_trigger > 0.3 ? POWER : 0.0;
        double feed = gamepad1.right_bumper ? -1.0 : gamepad1.left_trigger > 0.3 ? 1.0 : 0.0;
        if (shooterLeft != null) shooterLeft.setPower(shoot);
        if (shooterRight != null) shooterRight.setPower(shoot);
        if (intakeA != null) intakeA.setPower(feed);
        if (intakeB != null) intakeB.setPower(feed);

        telemetry.addData("Shooter", shoot > 0 ? "ON at %.0f %% power" : "off (hold the right trigger)", POWER * 100.0);
        telemetry.addData("shooterLeft", shooterLeft == null ? "NOT in the configuration" : String.format("%+.0f rpm", shooterLeft.getVelocity() / TICKS_PER_REV * 60.0));
        telemetry.addData("shooterRight", shooterRight == null ? "NOT in the configuration" : String.format("%+.0f rpm", shooterRight.getVelocity() / TICKS_PER_REV * 60.0));
        telemetry.addLine("The two speeds must be the same. If they differ, something slips.");
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
