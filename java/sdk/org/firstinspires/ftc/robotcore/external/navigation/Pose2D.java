package org.firstinspires.ftc.robotcore.external.navigation;

/** A position on the floor and a heading, as in the FTC SDK. */
public class Pose2D {
    private final double xMeters, yMeters, headingRadians;

    public Pose2D(DistanceUnit distanceUnit, double x, double y, AngleUnit headingUnit, double heading) {
        this.xMeters = distanceUnit.toMeters(x);
        this.yMeters = distanceUnit.toMeters(y);
        this.headingRadians = headingUnit.toRadians(heading);
    }

    public double getX(DistanceUnit unit) { return unit.fromMeters(xMeters); }
    public double getY(DistanceUnit unit) { return unit.fromMeters(yMeters); }
    public double getHeading(AngleUnit unit) { return unit.fromRadians(headingRadians); }
}
