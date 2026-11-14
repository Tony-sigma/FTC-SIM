package org.ftcsim;

import com.qualcomm.robotcore.hardware.DcMotor;
import com.qualcomm.robotcore.hardware.DcMotorEx;
import com.qualcomm.robotcore.hardware.DcMotorSimple;
import org.firstinspires.ftc.robotcore.external.navigation.AngleUnit;

/** A simulated motor with an encoder. Handles direction, run modes and RUN_TO_POSITION like the SDK does. */
public class SimMotor implements DcMotorEx {
    private final SimLink link;
    private final String name;
    private Direction direction = Direction.FORWARD;
    private RunMode mode = RunMode.RUN_WITHOUT_ENCODER;
    private ZeroPowerBehavior zero = ZeroPowerBehavior.BRAKE;
    private double power = 0, encoderOffset = 0, positionP = 0.006;
    private int target = 0, tolerance = 5;
    private boolean enabled = true, targetSet = false;

    public SimMotor(SimLink link, String name) { this.link = link; this.name = name; link.register(this); refresh(); }

    private double sign() { return direction == Direction.FORWARD ? 1.0 : -1.0; }

    /** Work out what to send to the simulator right now. */
    synchronized void refresh() {
        double out;
        if (!enabled || mode == RunMode.STOP_AND_RESET_ENCODER) out = 0;
        else if (mode == RunMode.RUN_TO_POSITION) {
            double error = target - getCurrentPosition();
            double limit = Math.abs(power);
            out = Math.max(-limit, Math.min(limit, error * positionP));
        } else out = power;
        link.setMotor(name, sign() * out);
    }
    synchronized void forceStop() { power = 0; }

    @Override public synchronized void setDirection(Direction d) { direction = d; refresh(); }
    @Override public Direction getDirection() { return direction; }
    @Override public synchronized void setPower(double p) { power = Math.max(-1.0, Math.min(1.0, p)); refresh(); }
    @Override public double getPower() { return power; }
    @Override public void setZeroPowerBehavior(ZeroPowerBehavior z) { zero = z; }
    @Override public ZeroPowerBehavior getZeroPowerBehavior() { return zero; }
    @Override public synchronized void setTargetPosition(int position) { target = position; targetSet = true; refresh(); }
    @Override public int getTargetPosition() { return target; }
    /** Busy until the motor is at the target AND has stopped moving, as with the real controller. */
    @Override public boolean isBusy() {
        return mode == RunMode.RUN_TO_POSITION && (Math.abs(target - getCurrentPosition()) > tolerance || Math.abs(link.motorTicksPerSecond(name)) > 40.0);
    }
    @Override public int getCurrentPosition() { return (int) Math.round(sign() * (link.motorTicks(name) - encoderOffset)); }
    @Override public synchronized void setMode(RunMode m) {
        if (m == RunMode.RUN_TO_POSITION && !targetSet)
            throw new IllegalStateException("Failed to switch motor \"" + name + "\" to RUN_TO_POSITION: call setTargetPosition() first.");
        if (m == RunMode.STOP_AND_RESET_ENCODER) encoderOffset = link.motorTicks(name);
        mode = m;
        refresh();
    }
    @Override public RunMode getMode() { return mode; }

    @Override public synchronized void setMotorEnable() { enabled = true; refresh(); }
    @Override public synchronized void setMotorDisable() { enabled = false; refresh(); }
    @Override public boolean isMotorEnabled() { return enabled; }
    @Override public void setVelocity(double ticksPerSecond) { setPower(ticksPerSecond / link.motorMaxTicksPerSecond(name)); }
    @Override public void setVelocity(double angularRate, AngleUnit unit) { setVelocity(angularRate); }
    @Override public double getVelocity() { return sign() * link.motorTicksPerSecond(name); }
    @Override public double getVelocity(AngleUnit unit) { return getVelocity(); }
    @Override public void setTargetPositionTolerance(int t) { tolerance = t; }
    @Override public int getTargetPositionTolerance() { return tolerance; }
    @Override public void setPositionPIDFCoefficients(double p) { positionP = p / 500.0; }
    @Override public void setVelocityPIDFCoefficients(double p, double i, double d, double f) { }
    @Override public boolean isOverCurrent() { return false; }
    @Override public String getDeviceName() { return "Simulated motor " + name; }
}
