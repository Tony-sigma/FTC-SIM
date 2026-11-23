package org.firstinspires.ftc.teamcode;

import com.qualcomm.robotcore.eventloop.opmode.OpMode;
import com.qualcomm.robotcore.eventloop.opmode.TeleOp;
import org.firstinspires.ftc.robotcore.external.hardware.camera.WebcamName;
import org.firstinspires.ftc.vision.VisionPortal;
import org.firstinspires.ftc.vision.apriltag.AprilTagClusterDetection;
import org.firstinspires.ftc.vision.apriltag.AprilTagDetection;
import org.firstinspires.ftc.vision.apriltag.AprilTagProcessor;
import org.firstinspires.ftc.vision.apriltag.AprilTagSingleDetection;

/**
 * TEST: the camera and the AprilTags. Nothing moves. Point the camera at a hive and read the screen.
 *
 * For every hive cell it can see (each cell has a cluster of four tags) it shows:
 *   - the cluster's name (RED AUDIENCE, RED SCORING, BLUE AUDIENCE, BLUE SCORING)
 *   - how many of its tags were read (percent)
 *   - range (inches to the cell's opening), bearing (degrees: + = it is to the LEFT) and elevation
 *   - roll, and from it whether the cell is the right way up, i.e. the raised one you can score in
 *
 * Use it to check the camera is found, that distances look right (measure one with a tape: if it is
 * off, the camera needs calibrating), and how far away the tags can still be read.
 */
@TeleOp(name = "Test: Camera", group = "Tests")
public class TestCamera extends OpMode {
    static final String CAMERA_NAME = "Webcam 1";

    private VisionPortal visionPortal;
    private AprilTagProcessor aprilTag;

    @Override
    public void init() {
        WebcamName camera = hardwareMap.tryGet(WebcamName.class, CAMERA_NAME);
        if (camera == null) {
            telemetry.addData(CAMERA_NAME, "NOT FOUND in the configuration");
            return;
        }
        // On the real robot an Arducam also needs .setLensIntrinsics(fx, fy, cx, cy) from its calibration.
        aprilTag = new AprilTagProcessor.Builder().build();
        visionPortal = new VisionPortal.Builder().setCamera(camera).addProcessor(aprilTag).build();
        telemetry.addLine("Camera started. Press start.");
    }

    @Override
    public void loop() {
        if (aprilTag == null) {
            telemetry.addData(CAMERA_NAME, "NOT FOUND in the configuration");
            return;
        }
        telemetry.addData("Camera", "%s", visionPortal.getCameraState());
        int count = 0;
        for (AprilTagDetection detection : aprilTag.getDetections()) {
            count++;
            if (detection instanceof AprilTagClusterDetection) {
                AprilTagClusterDetection cluster = (AprilTagClusterDetection) detection;
                boolean rightWayUp = Math.abs(detection.ftcPose.roll) < 90;
                telemetry.addLine(String.format("== %s  (%d%% of its tags)", cluster.metadata.name, cluster.percentClusterFound));
                telemetry.addLine(String.format("   range %.1f in   bearing %.1f   elevation %.1f", detection.ftcPose.range, detection.ftcPose.bearing, detection.ftcPose.elevation));
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
