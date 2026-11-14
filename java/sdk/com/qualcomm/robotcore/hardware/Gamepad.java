package com.qualcomm.robotcore.hardware;
/** Same public fields as the FTC SDK Gamepad. Stick Y is negative when pushed forward, as on the real robot. */
public class Gamepad {
    public volatile float left_stick_x, left_stick_y, right_stick_x, right_stick_y, left_trigger, right_trigger;
    public volatile boolean a, b, x, y, dpad_up, dpad_down, dpad_left, dpad_right;
    public volatile boolean left_bumper, right_bumper, left_stick_button, right_stick_button, start, back, guide;
    // PlayStation names for the same buttons
    public volatile boolean cross, circle, square, triangle, options, share, ps, touchpad;
    public boolean atRest() {
        return left_stick_x == 0 && left_stick_y == 0 && right_stick_x == 0 && right_stick_y == 0 && left_trigger == 0 && right_trigger == 0;
    }
    public void rumble(int durationMs) { }
    public void rumble(double rumble1, double rumble2, int durationMs) { }
    public void rumbleBlips(int count) { }
    public void stopRumble() { }
    public boolean isRumbling() { return false; }
    public void setLedColor(double r, double g, double b, int durationMs) { }
}
