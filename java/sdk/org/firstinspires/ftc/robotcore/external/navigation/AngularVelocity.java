package org.firstinspires.ftc.robotcore.external.navigation;
public class AngularVelocity {
    public AngleUnit unit = AngleUnit.DEGREES;
    public float xRotationRate, yRotationRate, zRotationRate;
    public long acquisitionTime;
    public AngularVelocity() { }
    public AngularVelocity(AngleUnit unit, float x, float y, float z, long acquisitionTime) {
        this.unit = unit; xRotationRate = x; yRotationRate = y; zRotationRate = z; this.acquisitionTime = acquisitionTime;
    }
}
