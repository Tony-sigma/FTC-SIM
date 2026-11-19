package org.firstinspires.ftc.vision.apriltag;
import org.firstinspires.ftc.robotcore.external.navigation.Pose3D;
/** A single AprilTag that is not part of a cluster. BIOBUZZ has none, so the simulator never returns one. */
public class AprilTagSingleDetection extends AprilTagDetection {
    public final int id;
    public final int hamming;
    public final float decisionMargin;
    public final AprilTagMetadata metadata;
    public AprilTagSingleDetection(int id, AprilTagMetadata metadata, AprilTagPoseFtc ftcPose, Pose3D robotPose, long time) {
        super(ftcPose, robotPose, time);
        this.id = id; this.hamming = 0; this.decisionMargin = 100f; this.metadata = metadata;
    }
}
