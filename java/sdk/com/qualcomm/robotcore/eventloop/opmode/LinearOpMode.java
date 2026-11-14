package com.qualcomm.robotcore.eventloop.opmode;

/** Simulator stand-in for the FTC SDK class of the same name. */
public abstract class LinearOpMode extends OpMode {
    public abstract void runOpMode() throws InterruptedException;

    public void waitForStart() {
        while (!isStarted() && !isStopRequested()) internalSimLink.waitForPacket();
    }
    public final boolean opModeIsActive() {
        boolean active = isStarted() && !isStopRequested();
        if (active) Thread.yield();
        return active;
    }
    public final boolean opModeInInit() { return !isStarted() && !isStopRequested(); }
    public final boolean isStarted() { return internalSimLink.isStarted(); }
    public final boolean isStopRequested() { return internalSimLink.isStopRequested() || Thread.currentThread().isInterrupted(); }
    public final void idle() { Thread.yield(); }
    public final void sleep(long milliseconds) {
        try { Thread.sleep(milliseconds); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
    }

    // The runner drives runOpMode() on its own thread; these are unused for linear OpModes.
    @Override public final void init() { }
    @Override public final void init_loop() { }
    @Override public final void start() { }
    @Override public final void loop() { }
    @Override public final void stop() { }
}
