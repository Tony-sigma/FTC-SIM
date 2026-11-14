package org.firstinspires.ftc.robotcore.external.navigation;
public class YawPitchRollAngles {
    private final AngleUnit unit; private final double yaw, pitch, roll; private final long time;
    public YawPitchRollAngles(AngleUnit angleUnit, double yaw, double pitch, double roll, long acquisitionTime) {
        this.unit = angleUnit; this.yaw = yaw; this.pitch = pitch; this.roll = roll; this.time = acquisitionTime;
    }
    public double getYaw() { return yaw; }
    public double getYaw(AngleUnit u) { return u.fromUnit(unit, yaw); }
    public double getPitch() { return pitch; }
    public double getPitch(AngleUnit u) { return u.fromUnit(unit, pitch); }
    public double getRoll() { return roll; }
    public double getRoll(AngleUnit u) { return u.fromUnit(unit, roll); }
    public long getAcquisitionTime() { return time; }
}
