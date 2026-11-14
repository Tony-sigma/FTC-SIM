package com.qualcomm.hardware.limelightvision;
public class LLStatus {
    private final int pipeline;
    LLStatus(int pipeline) { this.pipeline = pipeline; }
    public int getPipelineIndex() { return pipeline; }
    public String getPipelineType() { return "pipe_fiducial"; }
    public String getName() { return "limelight"; }
    public double getTemp() { return 45.0; }
    public double getCpu() { return 20.0; }
    public double getFps() { return 60.0; }
}
