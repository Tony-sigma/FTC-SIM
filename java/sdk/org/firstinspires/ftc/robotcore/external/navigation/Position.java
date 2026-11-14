package org.firstinspires.ftc.robotcore.external.navigation;
public class Position {
    public DistanceUnit unit;
    public double x, y, z;
    public long acquisitionTime;
    public Position() { this(DistanceUnit.MM, 0, 0, 0, 0); }
    public Position(DistanceUnit unit, double x, double y, double z, long acquisitionTime) {
        this.unit = unit; this.x = x; this.y = y; this.z = z; this.acquisitionTime = acquisitionTime;
    }
    public Position toUnit(DistanceUnit u) {
        return new Position(u, u.fromUnit(unit, x), u.fromUnit(unit, y), u.fromUnit(unit, z), acquisitionTime);
    }
    @Override public String toString() { return String.format("(%.3f %.3f %.3f)%s", x, y, z, unit); }
}
