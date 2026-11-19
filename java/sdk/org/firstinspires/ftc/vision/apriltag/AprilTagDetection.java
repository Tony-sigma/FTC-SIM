package org.firstinspires.ftc.vision.apriltag;
import org.firstinspires.ftc.robotcore.external.navigation.Pose3D;
/**
 * Something the AprilTagProcessor found. Since FTC SDK 12.0 every detection is one of two kinds:
 * AprilTagSingleDetection (a lone tag) or AprilTagClusterDetection (a group of tags, as on the BIOBUZZ
 * hive cells). Check which with instanceof and cast to read its metadata. The pose lives here.
 */
public class AprilTagDetection {
    public final AprilTagPoseFtc ftcPose;
    /** The robot's position on the field worked out from this detection. */
    public final Pose3D robotPose;
    public final long frameAcquisitionNanoTime;
    protected AprilTagDetection(AprilTagPoseFtc ftcPose, Pose3D robotPose, long time) {
        this.ftcPose = ftcPose; this.robotPose = robotPose; this.frameAcquisitionNanoTime = time;
    }
}
