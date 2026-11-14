package com.qualcomm.robotcore.eventloop.opmode;

import com.qualcomm.robotcore.hardware.Gamepad;
import com.qualcomm.robotcore.hardware.HardwareMap;
import org.firstinspires.ftc.robotcore.external.Telemetry;

/** Simulator stand-in for the FTC SDK class of the same name. */
public abstract class OpMode {
    public Gamepad gamepad1 = new Gamepad();
    public Gamepad gamepad2 = new Gamepad();
    public Telemetry telemetry;
    public HardwareMap hardwareMap;
    public double time = 0.0;

    /** Simulator plumbing; not part of the real SDK. */
    public org.ftcsim.SimLink internalSimLink;
    private long startNanos = System.nanoTime();

    public abstract void init();
    public void init_loop() { }
    public void start() { }
    public abstract void loop();
    public void stop() { }

    public double getRuntime() { return (System.nanoTime() - startNanos) / 1e9; }
    public void resetRuntime() { startNanos = System.nanoTime(); }
    public final void requestOpModeStop() { if (internalSimLink != null) internalSimLink.requestStop(); }
    public final void terminateOpModeNow() { requestOpModeStop(); throw new org.ftcsim.OpModeStopped(); }
    public void updateTelemetry(Telemetry t) { t.update(); }
}
