package org.firstinspires.ftc.vision.apriltag;
import org.firstinspires.ftc.robotcore.external.navigation.Pose3D;
/** One AprilTag the camera sees right now. */
public class AprilTagDetection {
    public final int id;
    public final int hamming;
    public final float decisionMargin;
    /** Non-null when the tag is a known one; check this before using ftcPose, as on the real robot. */
    public final AprilTagMetadata metadata;
    public final AprilTagPoseFtc ftcPose;
    /** The robot's position on the field worked out from this tag. */
    public final Pose3D robotPose;
    public final long frameAcquisitionNanoTime;
    public AprilTagDetection(int id, AprilTagMetadata metadata, AprilTagPoseFtc ftcPose, Pose3D robotPose, long time) {
        this.id = id; this.hamming = 0; this.decisionMargin = 100f; this.metadata = metadata; this.ftcPose = ftcPose;
        this.robotPose = robotPose; this.frameAcquisitionNanoTime = time;
    }
}
