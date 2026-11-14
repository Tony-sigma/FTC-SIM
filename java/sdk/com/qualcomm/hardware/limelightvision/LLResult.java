package com.qualcomm.hardware.limelightvision;
import java.util.*;
import org.firstinspires.ftc.robotcore.external.navigation.*;
/** What the Limelight saw at one moment. The "main" target (getTx/getTy/getTa) is the biggest tag in view. */
public class LLResult {
    private final List<LLResultTypes.FiducialResult> fiducials;
    private final Pose3D botpose;
    private final int pipeline;
    private final long created = System.nanoTime();
    LLResult(List<LLResultTypes.FiducialResult> fiducials, Pose3D botpose, int pipeline) { this.fiducials = fiducials; this.botpose = botpose; this.pipeline = pipeline; }
    public boolean isValid() { return !fiducials.isEmpty(); }
    public double getTx() { return fiducials.isEmpty() ? 0.0 : fiducials.get(0).getTargetXDegrees(); }
    public double getTy() { return fiducials.isEmpty() ? 0.0 : fiducials.get(0).getTargetYDegrees(); }
    public double getTa() { return fiducials.isEmpty() ? 0.0 : fiducials.get(0).getTargetArea(); }
    public List<LLResultTypes.FiducialResult> getFiducialResults() { return fiducials; }
    /** Robot position on the field worked out from the tags (metres, field centre = 0,0). Null-safe: zeros when no tag is seen. */
    public Pose3D getBotpose() { return botpose; }
    public Pose3D getBotpose_MT2() { return botpose; }
    public int getBotposeTagCount() { return fiducials.size(); }
    public int getPipelineIndex() { return pipeline; }
    public long getStaleness() { return (System.nanoTime() - created) / 1000000L; }
    public double getTimestamp() { return created / 1e9; }
    public double getCaptureLatency() { return 10.0; }
    public double getTargetingLatency() { return 10.0; }
}
