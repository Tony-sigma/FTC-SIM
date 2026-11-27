package org.firstinspires.ftc.teamcode;

import com.qualcomm.hardware.gobilda.GoBildaPinpointDriver;
import com.qualcomm.robotcore.eventloop.opmode.OpMode;
import com.qualcomm.robotcore.eventloop.opmode.TeleOp;
import org.firstinspires.ftc.robotcore.external.navigation.AngleUnit;
import org.firstinspires.ftc.robotcore.external.navigation.DistanceUnit;
import org.firstinspires.ftc.robotcore.external.navigation.Pose2D;

/**
 * TEST: the odometry (goBILDA Pinpoint + two 4-Bar pods). Nothing is powered: push and turn the
 * robot BY HAND and watch the numbers. Keep the robot still while it initialises.
 *
 *   A   set the position back to 0, 0, 0
 *
 * Checks, in this order:
 *   1. Status must say READY. FAULT_X_POD_NOT_DETECTED / FAULT_Y_POD_NOT_DETECTED = that pod's cable.
 *   2. Push the robot FORWARD one tile: X must go UP by about 24. If it goes down, flip X_POD_DIRECTION.
 *   3. Push the robot to its LEFT one tile: Y must go UP by about 24. If it goes down, flip Y_POD_DIRECTION.
 *   4. Turn the robot LEFT (counter-clockwise from above) a quarter turn: heading must go to about +90.
 *   5. Spin the robot on the spot a full turn: X and Y should come back close to where they were.
 *      If they wander by inches, the two pod offsets below are wrong.
 * When all five are right, copy the four settings into the TeleOps.
 */
@TeleOp(name = "Test: Odometry", group = "Tests")
public class TestOdometry extends OpMode {
    static final String PINPOINT_NAME = "pinpoint";
    /** How far LEFT of the robot's centre the forward (X) pod is, in mm. Right of centre = negative. From the CAD. */
    static final double X_POD_OFFSET_MM = -131.0;
    /** How far FORWARD of the robot's centre the sideways (Y) pod is, in mm. Behind the centre = negative. From the CAD. */
    static final double Y_POD_OFFSET_MM = -88.8;
    static final GoBildaPinpointDriver.EncoderDirection X_POD_DIRECTION = GoBildaPinpointDriver.EncoderDirection.FORWARD;
    static final GoBildaPinpointDriver.EncoderDirection Y_POD_DIRECTION = GoBildaPinpointDriver.EncoderDirection.FORWARD;

    private GoBildaPinpointDriver pinpoint;

    @Override
    public void init() {
        pinpoint = hardwareMap.tryGet(GoBildaPinpointDriver.class, PINPOINT_NAME);
        if (pinpoint == null) {
            telemetry.addLine(PINPOINT_NAME + " NOT FOUND in the configuration (I2C device: goBILDA Pinpoint Odometry Computer)");
            return;
        }
        pinpoint.setOffsets(X_POD_OFFSET_MM, Y_POD_OFFSET_MM, DistanceUnit.MM);
        pinpoint.setEncoderResolution(GoBildaPinpointDriver.GoBildaOdometryPods.goBILDA_4_BAR_POD);
        pinpoint.setEncoderDirections(X_POD_DIRECTION, Y_POD_DIRECTION);
        pinpoint.resetPosAndIMU();   // the robot must be standing still for this
        telemetry.addLine("Keep the robot still, then press start and push it by hand.");
    }

    @Override
    public void loop() {
        if (pinpoint == null) {
            telemetry.addData(PINPOINT_NAME, "NOT FOUND in the configuration");
            return;
        }
        if (gamepad1.a) pinpoint.setPosition(new Pose2D(DistanceUnit.INCH, 0, 0, AngleUnit.DEGREES, 0));
        pinpoint.update();
        Pose2D pose = pinpoint.getPosition();
        telemetry.addLine("Push by hand. A = back to zero.");
        telemetry.addData("Status", pinpoint.getDeviceStatus());
        telemetry.addData("X (forward)", "%.1f in", pose.getX(DistanceUnit.INCH));
        telemetry.addData("Y (left)", "%.1f in", pose.getY(DistanceUnit.INCH));
        telemetry.addData("Heading", "%.1f deg", pose.getHeading(AngleUnit.DEGREES));
    }
}
