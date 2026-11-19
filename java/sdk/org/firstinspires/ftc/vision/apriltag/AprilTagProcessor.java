package org.firstinspires.ftc.vision.apriltag;

import java.util.ArrayList;
import org.firstinspires.ftc.robotcore.external.navigation.*;
import org.firstinspires.ftc.vision.VisionPortal;
import org.firstinspires.ftc.vision.VisionProcessor;

/**
 * Simulator stand-in for the FTC SDK AprilTagProcessor (SDK 12.0 style). It reports the AprilTag
 * clusters the simulated camera can see, as AprilTagClusterDetection objects; nothing comes back until the processor is part of a built VisionPortal that is streaming.
 */
public class AprilTagProcessor implements VisionProcessor {
    public enum TagFamily { TAG_36h11, TAG_25h9, TAG_16h5, TAG_standard41h12 }
    public enum PoseSolver { APRILTAG_BUILTIN, OPENCV_ITERATIVE, OPENCV_SOLVEPNP_EPNP, OPENCV_IPPE, OPENCV_IPPE_SQUARE, OPENCV_SQPNP }

    private DistanceUnit distanceUnit = DistanceUnit.INCH;
    private AngleUnit angleUnit = AngleUnit.DEGREES;
    private VisionPortal portal;
    private org.ftcsim.SimLink link;
    private long lastFrame = -1;

    public static class Builder {
        private final AprilTagProcessor p = new AprilTagProcessor();
        public Builder setDrawAxes(boolean b) { return this; }
        public Builder setDrawCubeProjection(boolean b) { return this; }
        public Builder setDrawTagOutline(boolean b) { return this; }
        public Builder setDrawTagID(boolean b) { return this; }
        public Builder setTagFamily(TagFamily family) { return this; }
        public Builder setTagLibrary(AprilTagLibrary library) { return this; }
        public Builder setNumThreads(int threads) { return this; }
        public Builder setSuppressCalibrationWarnings(boolean b) { return this; }
        /** Lens calibration. Needed on the real robot for an Arducam; the simulator does not use it. */
        public Builder setLensIntrinsics(double fx, double fy, double cx, double cy) { return this; }
        /** Where the camera sits on the robot. The simulator takes this from robot_config.json instead. */
        public Builder setCameraPose(Position position, YawPitchRollAngles orientation) { return this; }
        public Builder setOutputUnits(DistanceUnit distanceUnit, AngleUnit angleUnit) { p.distanceUnit = distanceUnit; p.angleUnit = angleUnit; return this; }
        public AprilTagProcessor build() { return p; }
    }

    public static AprilTagProcessor easyCreateWithDefaults() { return new Builder().build(); }

    /** Simulator plumbing, called by VisionPortal.Builder.build(). */
    public void internalAttach(VisionPortal portal, org.ftcsim.SimLink link) { this.portal = portal; this.link = link; }

    public void setDecimation(float decimation) { }
    public void setPoseSolver(PoseSolver solver) { }
    public int getPerTagAvgPoseSolveTime() { return 5; }

    /** Every cluster in view right now, biggest first. Empty when none is visible. */
    public ArrayList<AprilTagDetection> getDetections() {
        ArrayList<AprilTagDetection> out = new ArrayList<>();
        if (portal == null || link == null || !portal.internalIsLive(this)) return out;
        double[] rp = link.cameraRobotPose();
        long now = System.nanoTime();
        Pose3D robotPose = new Pose3D(
            new Position(distanceUnit, distanceUnit.fromMeters(rp[0]), distanceUnit.fromMeters(rp[1]), 0.0, now),
            new YawPitchRollAngles(AngleUnit.DEGREES, rp[2], 0, 0, now));
        java.util.List<String> names = link.cameraClusterNames();
        java.util.List<double[]> rows = link.cameraTags();
        for (int i = 0; i < rows.size() && i < names.size(); i++) {
            // row = {percent found, x, y, z, roll} with x right, y out of the lens, z up, in inches
            double[] t = rows.get(i);
            double x = distanceUnit.fromInches(t[1]), y = distanceUnit.fromInches(t[2]), z = distanceUnit.fromInches(t[3]);
            double range = Math.hypot(x, y);
            double bearing = Math.atan2(-x, y), elevation = Math.atan2(z, y);
            AprilTagPoseFtc pose = new AprilTagPoseFtc(x, y, z, 0, 0, angleUnit.fromDegrees(t[4]), range,
                angleUnit.fromRadians(bearing), angleUnit.fromRadians(elevation));
            out.add(new AprilTagClusterDetection(t[0], new AprilTagMetadata(-1, names.get(i), 3.27, DistanceUnit.INCH), pose, robotPose, now));
        }
        return out;
    }

    /** The detections, but only once per new camera frame; null if there is nothing new yet. */
    public ArrayList<AprilTagDetection> getFreshDetections() {
        if (link == null) return null;
        long frame = link.packetCount();
        if (frame == lastFrame) return null;
        lastFrame = frame;
        return getDetections();
    }
}
