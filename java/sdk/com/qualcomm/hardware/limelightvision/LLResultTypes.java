package com.qualcomm.hardware.limelightvision;
import org.firstinspires.ftc.robotcore.external.navigation.Pose3D;
public class LLResultTypes {
    /** One AprilTag the camera can see. */
    public static class FiducialResult {
        private final int id; private final double tx, ty, ta; private final Pose3D robotPose;
        FiducialResult(int id, double tx, double ty, double ta, Pose3D robotPose) { this.id = id; this.tx = tx; this.ty = ty; this.ta = ta; this.robotPose = robotPose; }
        public int getFiducialId() { return id; }
        public String getFamily() { return "36H11"; }
        public double getTargetXDegrees() { return tx; }
        public double getTargetYDegrees() { return ty; }
        public double getTargetArea() { return ta; }
        public Pose3D getRobotPoseFieldSpace() { return robotPose; }
    }
}
