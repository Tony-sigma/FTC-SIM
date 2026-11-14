package org.ftcsim;

import com.qualcomm.robotcore.hardware.IMU;
import org.firstinspires.ftc.robotcore.external.navigation.AngleUnit;
import org.firstinspires.ftc.robotcore.external.navigation.AngularVelocity;
import org.firstinspires.ftc.robotcore.external.navigation.YawPitchRollAngles;

/** Yaw only: counter-clockwise positive, zero where the robot faced at resetYaw() (or at the start). */
public class SimIMU implements IMU {
    private final SimLink link;
    private double zero = 0;
    public SimIMU(SimLink link) { this.link = link; }
    @Override public boolean initialize(Parameters parameters) { return true; }
    @Override public void resetYaw() { zero = link.yawDeg(); }
    @Override public YawPitchRollAngles getRobotYawPitchRollAngles() {
        return new YawPitchRollAngles(AngleUnit.DEGREES, AngleUnit.normalizeDegrees(link.yawDeg() - zero), 0, 0, System.nanoTime());
    }
    @Override public AngularVelocity getRobotAngularVelocity(AngleUnit unit) {
        float z = (float) (unit == AngleUnit.DEGREES ? link.yawRateDeg() : Math.toRadians(link.yawRateDeg()));
        return new AngularVelocity(unit, 0, 0, z, System.nanoTime());
    }
    @Override public String getDeviceName() { return "Simulated IMU"; }
}
