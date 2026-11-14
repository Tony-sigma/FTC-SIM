package com.qualcomm.robotcore.hardware;
import org.firstinspires.ftc.robotcore.external.navigation.AngleUnit;
public interface DcMotorEx extends DcMotor {
    void setMotorEnable();
    void setMotorDisable();
    boolean isMotorEnabled();
    /** Target speed in encoder ticks per second. */
    void setVelocity(double angularRate);
    void setVelocity(double angularRate, AngleUnit unit);
    /** Measured speed in encoder ticks per second. */
    double getVelocity();
    double getVelocity(AngleUnit unit);
    void setTargetPositionTolerance(int tolerance);
    int getTargetPositionTolerance();
    void setPositionPIDFCoefficients(double p);
    void setVelocityPIDFCoefficients(double p, double i, double d, double f);
    boolean isOverCurrent();
}
