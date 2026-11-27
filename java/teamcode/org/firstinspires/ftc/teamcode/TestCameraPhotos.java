package org.firstinspires.ftc.teamcode;

import android.util.Size;
import com.qualcomm.robotcore.eventloop.opmode.OpMode;
import com.qualcomm.robotcore.eventloop.opmode.TeleOp;
import org.firstinspires.ftc.robotcore.external.hardware.camera.WebcamName;
import org.firstinspires.ftc.vision.VisionPortal;

/**
 * TOOL: take photos with a camera, for its lens calibration. Nothing moves.
 *
 *   Before start:  X = camera 1,  B = camera 2
 *   After start:   A = take a photo
 *
 * A camera whose model the FTC software does not know (an Arducam, for example) reports wrong
 * distances until you give it four numbers that describe its lens: fx, fy, cx, cy. To get them:
 *   0. This camera has a lens you focus by turning it. Focus it first (sharp at about 5 feet) and fix
 *      it with a drop of glue or tape: turning the lens later makes the calibration wrong.
 *   1. Set WIDTH / HEIGHT / USE_MJPEG below to exactly what the camera will use on the robot.
 *   2. Run this, and photograph the calibration pattern your calibration program asks for, from
 *      many angles and distances (the FTC docs walk through the free 3DF Zephyr for Windows:
 *      Utilities, Images, Camera Calibration).
 *   3. Plug the Control Hub into a computer with a USB cable. The photos are in the top folder of
 *      its storage, named VisionPortal-Camera1-000000.png and so on.
 *   4. Give the photos to the calibration program. It answers with fx, fy, cx, cy.
 *   5. Type them into LENS in "Test: Camera", check the distance with a tape, then copy them to
 *      BiobuzzTeleOp.
 * The numbers only fit this camera at this picture size. Change the size and you calibrate again.
 */
@TeleOp(name = "Test: Camera Photos", group = "Tests")
public class TestCameraPhotos extends OpMode {
    static final String[] CAMERA_NAMES = {"Webcam 1", "Webcam 2"};
    static final int WIDTH = 640, HEIGHT = 480;
    static final boolean USE_MJPEG = true;

    private VisionPortal visionPortal;
    private int chosen = 0, photos = 0;
    private boolean found = false, lastA = false;

    @Override
    public void init() {
        telemetry.addLine("X = camera 1, B = camera 2, then press start.");
    }

    @Override
    public void init_loop() {
        if (gamepad1.x) chosen = 0;
        if (gamepad1.b) chosen = 1;
        telemetry.addLine("X = camera 1, B = camera 2, then press start.");
        telemetry.addData("Will use", "camera %d, \"%s\"%s", chosen + 1, CAMERA_NAMES[chosen],
            hardwareMap.tryGet(WebcamName.class, CAMERA_NAMES[chosen]) == null ? "  (NOT FOUND in the configuration)" : "");
    }

    @Override
    public void start() {
        WebcamName camera = hardwareMap.tryGet(WebcamName.class, CAMERA_NAMES[chosen]);
        if (camera == null) return;
        found = true;
        visionPortal = new VisionPortal.Builder()
            .setCamera(camera)
            .setCameraResolution(new Size(WIDTH, HEIGHT))
            .setStreamFormat(USE_MJPEG ? VisionPortal.StreamFormat.MJPEG : VisionPortal.StreamFormat.YUY2)
            .build();
    }

    @Override
    public void loop() {
        if (!found) {
            telemetry.addData(CAMERA_NAMES[chosen], "NOT FOUND in the configuration");
            return;
        }
        if (gamepad1.a && !lastA && visionPortal.getCameraState() == VisionPortal.CameraState.STREAMING) {
            visionPortal.saveNextFrameRaw(String.format("Camera%d-%06d", chosen + 1, photos));
            photos++;
        }
        lastA = gamepad1.a;
        telemetry.addData("Camera", "%d \"%s\"  %s", chosen + 1, CAMERA_NAMES[chosen], visionPortal.getCameraState());
        telemetry.addData("Picture", "%dx%d %s", WIDTH, HEIGHT, USE_MJPEG ? "MJPEG" : "YUY2");
        telemetry.addData("Photos taken (A)", photos);
    }

    @Override
    public void stop() {
        if (visionPortal != null) visionPortal.close();
    }
}
