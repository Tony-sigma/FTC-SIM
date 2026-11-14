package org.firstinspires.ftc.robotcore.external.navigation;
public enum DistanceUnit {
    METER(1.0), CM(0.01), MM(0.001), INCH(0.0254);
    public static final double infinity = Double.MAX_VALUE;
    private final double meters;
    DistanceUnit(double meters) { this.meters = meters; }
    public double fromMeters(double m) { return m / meters; }
    public double fromInches(double in) { return in * 0.0254 / meters; }
    public double fromCm(double cm) { return cm * 0.01 / meters; }
    public double fromMm(double mm) { return mm * 0.001 / meters; }
    public double fromUnit(DistanceUnit them, double theirs) { return theirs * them.meters / meters; }
    public double toMeters(double v) { return v * meters; }
    public double toInches(double v) { return v * meters / 0.0254; }
    public double toCm(double v) { return v * meters / 0.01; }
    public double toMm(double v) { return v * meters / 0.001; }
}
