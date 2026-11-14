package com.qualcomm.robotcore.util;
public class Range {
    public static double clip(double number, double min, double max) { return number < min ? min : (number > max ? max : number); }
    public static float clip(float number, float min, float max) { return number < min ? min : (number > max ? max : number); }
    public static int clip(int number, int min, int max) { return number < min ? min : (number > max ? max : number); }
    public static double scale(double n, double x1, double x2, double y1, double y2) {
        double a = (y1 - y2) / (x1 - x2);
        return a * n + (y1 - x1 * a);
    }
}
