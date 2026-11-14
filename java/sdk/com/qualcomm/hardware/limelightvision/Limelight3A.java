package com.qualcomm.hardware.limelightvision;
import com.qualcomm.robotcore.hardware.HardwareDevice;
import java.util.*;
import org.firstinspires.ftc.robotcore.external.navigation.*;
/**
 * Simulator stand-in for the FTC SDK Limelight class (used for the Limelight 3A and 4).
 * As with the real one, getLatestResult() gives nothing until you call start().
 */
public class Limelight3A implements HardwareDevice {
    private final org.ftcsim.SimLink link;
    private boolean running = false;
    private int pipeline = 0;
    public Limelight3A(org.ftcsim.SimLink link) { this.link = link; }
    public void start() { running = true; }
    public void pause() { running = false; }
    public void stop() { running = false; }
    public boolean isRunning() { return running; }
    public boolean isConnected() { return true; }
    public boolean pipelineSwitch(int index) { pipeline = index; return true; }
    public void setPollRateHz(int rateHz) { }
    public boolean updateRobotOrientation(double yaw) { return true; }
    public LLStatus getStatus() { return new LLStatus(pipeline); }
    public long getTimeSinceLastUpdate() { return 16; }
    public void shutdown() { running = false; }
    public LLResult getLatestResult() {
        if (!running) return null;
        double[] p = link.limelightPose();
        Pose3D pose = new Pose3D(new Position(DistanceUnit.METER, p[0], p[1], 0.0, System.nanoTime()),
            new YawPitchRollAngles(AngleUnit.DEGREES, p[2], 0, 0, System.nanoTime()));
        List<LLResultTypes.FiducialResult> list = new ArrayList<>();
        for (double[] t : link.limelightTags()) list.add(new LLResultTypes.FiducialResult((int) t[0], t[1], t[2], t[3], pose));
        return new LLResult(list, pose, pipeline);
    }
    @Override public String getDeviceName() { return "Simulated Limelight"; }
}
