package org.firstinspires.ftc.teamcode;

import android.util.Size;
import com.qualcomm.robotcore.eventloop.opmode.OpMode;
import com.qualcomm.robotcore.eventloop.opmode.TeleOp;
import org.firstinspires.ftc.robotcore.external.hardware.camera.WebcamName;
import org.firstinspires.ftc.vision.VisionPortal;
import org.firstinspires.ftc.vision.apriltag.AprilTagClusterDetection;
import org.firstinspires.ftc.vision.apriltag.AprilTagDetection;
import org.firstinspires.ftc.vision.apriltag.AprilTagProcessor;
import org.firstinspires.ftc.vision.apriltag.AprilTagSingleDetection;

/**
 * TEST: one camera and the AprilTags. Nothing moves.
 *
 *   Before start:  X = test camera 1,  B = test camera 2  (only one camera is opened at a time)
 *   After start:   point the camera at a hive and read the screen.
 *
 * To SEE what the camera sees: before pressing start, open the Driver Station menu (three dots) and
 * choose Camera Stream. Tap the picture to refresh it.
 *
 * For every hive cell it can see (each cell has a cluster of four tags) it shows:
 *   - the cluster's name (RED AUDIENCE, RED SCORING, BLUE AUDIENCE, BLUE SCORING)
 *   - how many of its tags were read (percent)
 *   - distance (straight line, inches, camera to the cell's opening) and bearing (+ = it is to the LEFT)
 *   - roll, and from it whether the cell is the right way up, i.e. the raised one you can score in
 *
 * Checks:
 *   1. "Camera" must reach STREAMING. If it never does, this camera does not offer the picture size
 *      below in the chosen format: flip USE_MJPEG and try again. (The team's HBVCAM-W20282GS is most
 *      likely an OV9281 global-shutter camera; the FTC docs list that sensor as needing MJPEG for
 *      640x480 and offering the normal YUY2 format only at 1280x720 and 1280x800.)
 *   2. Tags are found and named: the camera and the cable are fine.
 *   3. Measure the distance from the lens to a cell opening with a tape. If the screen disagrees by
 *      more than an inch or two, the camera needs its lens calibration (LENS below). Bearing is
 *      roughly right even without it; distance is not.
 */
@TeleOp(name = "Test: Camera", group = "Tests")
public class TestCamera extends OpMode {
    // ============ CAMERA SETTINGS: copy the ones that work into BiobuzzTeleOp ============
    /** Names in the robot configuration: camera 1 (on the shooter), camera 2 (on the chassis). */
    static final String[] CAMERA_NAMES = {"Webcam 1", "Webcam 2"};
    /** Picture size. The lens calibration only fits the size it was made for. */
    static final int WIDTH = 640, HEIGHT = 480;
    /** true = MJPEG, which an OV9281 camera needs for this size. false = the normal format (YUY2). */
    static final boolean USE_MJPEG = true;
    /**
     * Lens calibration for each camera: fx, fy, cx, cy at the picture size above (see "Test: Camera
     * Photos" for how to get them). All zeros = none yet: the SDK then uses its own values if it
     * knows this camera model, and otherwise warns that distances will be wrong.
     */
    static final double[][] LENS = {
        {0, 0, 0, 0},   // camera 1
        {0, 0, 0, 0},   // camera 2
    };
    // ===================================================================================

    private VisionPortal visionPortal;
    private AprilTagProcessor aprilTag;
    private int chosen = 0;
    private boolean found = false;

    @Override
    public void init() {
        telemetry.addLine("X = camera 1, B = camera 2, then press start.");
    }

    @Override
    public void init_loop() {
        if (gamepad1.x) chosen = 0;
        if (gamepad1.b) chosen = 1;
        telemetry.addLine("X = camera 1, B = camera 2, then press start.");
        telemetry.addData("Will test", "camera %d, \"%s\"%s", chosen + 1, CAMERA_NAMES[chosen],
            hardwareMap.tryGet(WebcamName.class, CAMERA_NAMES[chosen]) == null ? "  (NOT FOUND in the configuration)" : "");
    }

    @Override
    public void start() {
        WebcamName camera = hardwareMap.tryGet(WebcamName.class, CAMERA_NAMES[chosen]);
        if (camera == null) return;
        found = true;
        AprilTagProcessor.Builder tags = new AprilTagProcessor.Builder();
        double[] lens = LENS[chosen];
        if (lens[0] > 0) tags.setLensIntrinsics(lens[0], lens[1], lens[2], lens[3]);
        aprilTag = tags.build();
        visionPortal = new VisionPortal.Builder()
            .setCamera(camera)
            .setCameraResolution(new Size(WIDTH, HEIGHT))
            .setStreamFormat(USE_MJPEG ? VisionPortal.StreamFormat.MJPEG : VisionPortal.StreamFormat.YUY2)
            .addProcessor(aprilTag)
            .build();
    }

    @Override
    public void loop() {
        if (!found) {
            telemetry.addData(CAMERA_NAMES[chosen], "NOT FOUND in the configuration");
            return;
        }
        telemetry.addData("Camera", "%d \"%s\"  %s  %.0f pictures/s", chosen + 1, CAMERA_NAMES[chosen], visionPortal.getCameraState(), visionPortal.getFps());
        telemetry.addData("Picture", "%dx%d %s, lens calibration %s", WIDTH, HEIGHT, USE_MJPEG ? "MJPEG" : "YUY2", LENS[chosen][0] > 0 ? "from this file" : "none set here");
        int count = 0;
        for (AprilTagDetection detection : aprilTag.getDetections()) {
            count++;
            if (detection instanceof AprilTagClusterDetection) {
                AprilTagClusterDetection cluster = (AprilTagClusterDetection) detection;
                String name = cluster.metadata == null ? "unknown cluster" : cluster.metadata.name;
                telemetry.addLine(String.format("== %s  (%d%% of its tags)", name, cluster.percentClusterFound));
                if (detection.ftcPose == null) {
                    telemetry.addLine("   seen, but no position for it");
                    continue;
                }
                double distance = Math.sqrt(detection.ftcPose.x * detection.ftcPose.x + detection.ftcPose.y * detection.ftcPose.y + detection.ftcPose.z * detection.ftcPose.z);
                boolean rightWayUp = Math.abs(detection.ftcPose.roll) < 90;
                telemetry.addLine(String.format("   distance %.1f in   bearing %.1f   elevation %.1f", distance, detection.ftcPose.bearing, detection.ftcPose.elevation));
                telemetry.addLine(String.format("   roll %.0f  ->  %s", detection.ftcPose.roll, rightWayUp ? "RAISED cell, can score" : "lowered cell, do not aim here"));
            } else if (detection instanceof AprilTagSingleDetection) {
                AprilTagSingleDetection single = (AprilTagSingleDetection) detection;
                telemetry.addLine(String.format("== single tag, ID %d", single.id));
            }
        }
        if (count == 0) telemetry.addLine("No tags in view.");
    }

    @Override
    public void stop() {
        if (visionPortal != null) visionPortal.close();
    }
}
