package android.util;
/** Stand-in for the Android class, so setCameraResolution(new Size(640, 480)) compiles. */
public final class Size {
    private final int width, height;
    public Size(int width, int height) { this.width = width; this.height = height; }
    public int getWidth() { return width; }
    public int getHeight() { return height; }
    @Override public String toString() { return width + "x" + height; }
}
