package org.ftcsim;

import com.qualcomm.robotcore.hardware.Servo;

public class SimServo implements Servo {
    private final SimLink link;
    private final String name;
    private Direction direction = Direction.FORWARD;
    private double position = Double.NaN, min = 0.0, max = 1.0;

    public SimServo(SimLink link, String name) { this.link = link; this.name = name; }

    @Override public void setDirection(Direction d) { direction = d; if (!Double.isNaN(position)) setPosition(position); }
    @Override public Direction getDirection() { return direction; }
    @Override public void setPosition(double p) {
        position = Math.max(0.0, Math.min(1.0, p));
        double scaled = min + position * (max - min);
        link.setServo(name, direction == Direction.FORWARD ? scaled : 1.0 - scaled);
    }
    /** Like a real servo: this is the last position you commanded, not a measurement. */
    @Override public double getPosition() { return position; }
    @Override public void scaleRange(double mn, double mx) { min = mn; max = mx; }
    @Override public String getDeviceName() { return "Simulated servo " + name; }
}
