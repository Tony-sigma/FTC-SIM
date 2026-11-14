package com.qualcomm.robotcore.util;
public class ElapsedTime {
    public enum Resolution { SECONDS, MILLISECONDS }
    private long start = System.nanoTime();
    private final Resolution resolution;
    public ElapsedTime() { this(Resolution.SECONDS); }
    public ElapsedTime(Resolution resolution) { this.resolution = resolution; }
    public void reset() { start = System.nanoTime(); }
    public double seconds() { return (System.nanoTime() - start) / 1e9; }
    public double milliseconds() { return (System.nanoTime() - start) / 1e6; }
    public long nanoseconds() { return System.nanoTime() - start; }
    public double time() { return resolution == Resolution.SECONDS ? seconds() : milliseconds(); }
    public double startTime() { return start / 1e9; }
    @Override public String toString() { return String.format("%1.4f seconds", seconds()); }
}
