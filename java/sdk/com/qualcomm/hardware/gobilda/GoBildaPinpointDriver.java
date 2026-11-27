package com.qualcomm.hardware.gobilda;

import org.firstinspires.ftc.robotcore.external.navigation.AngleUnit;
import org.firstinspires.ftc.robotcore.external.navigation.DistanceUnit;
import org.firstinspires.ftc.robotcore.external.navigation.Pose2D;

/**
 * Simulator stand-in for the FTC SDK's goBILDA Pinpoint driver. As on the real device, readings only
 * change when update() is called, X is forward and Y is to the LEFT of where the robot pointed when
 * the position was last set, and the heading is counter-clockwise. The simulated pods are perfect; a
 * pod set to count the wrong way (EncoderDirection) reads backwards, as it would on the robot.
 */
public class GoBildaPinpointDriver {
    public enum DeviceStatus { NOT_READY, READY, CALIBRATING, FAULT_X_POD_NOT_DETECTED, FAULT_Y_POD_NOT_DETECTED, FAULT_NO_PODS_DETECTED, FAULT_IMU_RUNAWAY, FAULT_BAD_READ }
    public enum EncoderDirection { FORWARD, REVERSED }
    public enum GoBildaOdometryPods { goBILDA_SWINGARM_POD, goBILDA_4_BAR_POD }
    public enum ReadData { ONLY_UPDATE_HEADING }

    private final org.ftcsim.SimLink link;
    private double xOffsetMm, yOffsetMm, yawScalar = 1.0;
    private EncoderDirection xDirection = EncoderDirection.FORWARD, yDirection = EncoderDirection.FORWARD;
    // Where the robot really was (field inches / degrees) when the position was last set, and what it was set to.
    private double[] fieldRef = {0, 0, 0}, outRef = {0, 0, 0};
    private double x, y, heading, velX, velY, velHeading, lastTime = -1;

    public GoBildaPinpointDriver(org.ftcsim.SimLink link) {
        this.link = link;
        fieldRef = link.pinpointPose().clone();
    }

    /** Read the device. Call this once every loop. */
    public void update() {
        double[] f = link.pinpointPose();
        double refHeading = Math.toRadians(fieldRef[2]);
        double dx = f[0] - fieldRef[0], dy = f[1] - fieldRef[1];
        // Movement since the reference, as forward / left of the way the robot pointed then.
        double fwd = dx * Math.cos(refHeading) + dy * Math.sin(refHeading);
        double left = -dx * Math.sin(refHeading) + dy * Math.cos(refHeading);
        if (xDirection == EncoderDirection.REVERSED) fwd = -fwd;
        if (yDirection == EncoderDirection.REVERSED) left = -left;
        double outHeading = Math.toRadians(outRef[2]);
        double nx = outRef[0] + fwd * Math.cos(outHeading) - left * Math.sin(outHeading);
        double ny = outRef[1] + fwd * Math.sin(outHeading) + left * Math.cos(outHeading);
        double nh = AngleUnit.normalizeDegrees(outRef[2] + (f[2] - fieldRef[2]) * yawScalar);
        double now = link.simTime();
        if (lastTime >= 0 && now > lastTime) {
            double dt = now - lastTime;
            velX = (nx - x) / dt;
            velY = (ny - y) / dt;
            velHeading = AngleUnit.normalizeDegrees(nh - heading) / dt;
        }
        lastTime = now;
        x = nx; y = ny; heading = nh;
    }
    public void update(ReadData data) { update(); }

    public void setOffsets(double xOffset, double yOffset, DistanceUnit unit) { xOffsetMm = unit.toMm(xOffset); yOffsetMm = unit.toMm(yOffset); }
    public void setEncoderResolution(GoBildaOdometryPods pods) { }
    public void setEncoderResolution(double ticksPerUnit, DistanceUnit unit) { }
    public void setEncoderDirections(EncoderDirection xEncoder, EncoderDirection yEncoder) { xDirection = xEncoder; yDirection = yEncoder; }
    public void setYawScalar(double scalar) { yawScalar = scalar; }
    public void recalibrateIMU() { }
    public void resetPosAndIMU() { setPosition(new Pose2D(DistanceUnit.INCH, 0, 0, AngleUnit.DEGREES, 0)); }
    public void setPosition(Pose2D pose) {
        fieldRef = link.pinpointPose().clone();
        outRef = new double[]{pose.getX(DistanceUnit.INCH), pose.getY(DistanceUnit.INCH), pose.getHeading(AngleUnit.DEGREES)};
        x = outRef[0]; y = outRef[1]; heading = outRef[2];
        velX = velY = velHeading = 0;
    }

    public DeviceStatus getDeviceStatus() { return DeviceStatus.READY; }
    public int getDeviceID() { return 1; }
    public int getDeviceVersion() { return 1; }
    public double getYawScalar() { return yawScalar; }
    public double getFrequency() { return 1500.0; }
    public Pose2D getPosition() { return new Pose2D(DistanceUnit.INCH, x, y, AngleUnit.DEGREES, heading); }
    public double getPosX(DistanceUnit unit) { return unit.fromInches(x); }
    public double getPosY(DistanceUnit unit) { return unit.fromInches(y); }
    public double getHeading(AngleUnit unit) { return unit.fromDegrees(heading); }
    public double getVelX(DistanceUnit unit) { return unit.fromInches(velX); }
    public double getVelY(DistanceUnit unit) { return unit.fromInches(velY); }
    public double getXOffset(DistanceUnit unit) { return unit.fromMm(xOffsetMm); }
    public double getYOffset(DistanceUnit unit) { return unit.fromMm(yOffsetMm); }
}
