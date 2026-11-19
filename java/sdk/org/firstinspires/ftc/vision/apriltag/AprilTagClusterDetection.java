package org.firstinspires.ftc.vision.apriltag;
import org.firstinspires.ftc.robotcore.external.navigation.Pose3D;
/**
 * A cluster of AprilTags seen as one thing. On BIOBUZZ each hive cell has a 4-tag cluster and its pose
 * points at the centre of that cell's opening. metadata.name is "RED AUDIENCE", "RED SCORING",
 * "BLUE AUDIENCE" or "BLUE SCORING"; metadata is never null for a cluster.
 */
public class AprilTagClusterDetection extends AprilTagDetection {
    /** How much of the cluster was seen, 0 to 100 (four tags: 25, 50, 75 or 100). */
    public final double percentClusterFound;
    public final AprilTagMetadata metadata;
    public AprilTagClusterDetection(double percentClusterFound, AprilTagMetadata metadata, AprilTagPoseFtc ftcPose, Pose3D robotPose, long time) {
        super(ftcPose, robotPose, time);
        this.percentClusterFound = percentClusterFound; this.metadata = metadata;
    }
}
