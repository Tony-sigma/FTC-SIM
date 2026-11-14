package org.firstinspires.ftc.robotcore.external.navigation;
public enum AngleUnit {
    DEGREES, RADIANS;
    public double fromDegrees(double degrees) { return this == DEGREES ? normalize(degrees) : normalize(Math.toRadians(degrees)); }
    public double fromRadians(double radians) { return this == RADIANS ? normalize(radians) : normalize(Math.toDegrees(radians)); }
    public double toDegrees(double angle) { return this == DEGREES ? normalize(angle) : DEGREES.normalize(Math.toDegrees(angle)); }
    public double toRadians(double angle) { return this == RADIANS ? normalize(angle) : RADIANS.normalize(Math.toRadians(angle)); }
    public double fromUnit(AngleUnit them, double theirs) { return them == DEGREES ? fromDegrees(theirs) : fromRadians(theirs); }
    public double normalize(double angle) { return this == DEGREES ? normalizeDegrees(angle) : normalizeRadians(angle); }
    public static double normalizeDegrees(double degrees) {
        while (degrees >= 180.0) degrees -= 360.0;
        while (degrees < -180.0) degrees += 360.0;
        return degrees;
    }
    public static double normalizeRadians(double radians) {
        while (radians >= Math.PI) radians -= 2.0 * Math.PI;
        while (radians < -Math.PI) radians += 2.0 * Math.PI;
        return radians;
    }
}
