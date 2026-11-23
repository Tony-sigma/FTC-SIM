package org.firstinspires.ftc.teamcode;

import com.qualcomm.hardware.rev.RevHubOrientationOnRobot;
import com.qualcomm.robotcore.eventloop.opmode.OpMode;
import com.qualcomm.robotcore.eventloop.opmode.TeleOp;
import com.qualcomm.robotcore.hardware.DcMotor;
import com.qualcomm.robotcore.hardware.IMU;
import org.firstinspires.ftc.robotcore.external.navigation.AngleUnit;

/**
 * TEST: the IMU and the encoders. Nothing is powered: push and turn the robot BY HAND and watch.
 *
 *   X   reset the heading to 0
 *
 * Checks:
 *   - turn the robot LEFT (counter-clockwise from above): the heading should go UP. If it goes down
 *     or barely changes, the hub orientation below (LOGO / USB direction) does not match how the
 *     Control Hub is mounted.
 *   - roll the robot FORWARD: every drive encoder should go UP (with the same motor directions as
 *     your TeleOp).
 * Odometry pods plugged into a goBILDA Pinpoint are read through the Pinpoint driver, not here; the
 * odoX / odoY lines only show up if pods are wired straight into motor encoder ports.
 */
@TeleOp(name = "Test: Sensors", group = "Tests")
public class TestSensors extends OpMode {
    static final String[] ENCODERS = {"frontLeft", "frontRight", "backLeft", "backRight", "odoX", "odoY"};

    private IMU imu;
    private final DcMotor[] motors = new DcMotor[ENCODERS.length];

    @Override
    public void init() {
        imu = hardwareMap.tryGet(IMU.class, "imu");
        if (imu != null) {
            // Change these two to match how YOUR Control Hub is mounted on the robot.
            imu.initialize(new IMU.Parameters(new RevHubOrientationOnRobot(
                RevHubOrientationOnRobot.LogoFacingDirection.UP, RevHubOrientationOnRobot.UsbFacingDirection.FORWARD)));
            imu.resetYaw();
        }
        for (int i = 0; i < ENCODERS.length; i++) motors[i] = hardwareMap.tryGet(DcMotor.class, ENCODERS[i]);
        telemetry.addLine("Motors stay off. Press start, then move the robot by hand.");
    }

    @Override
    public void loop() {
        if (imu == null) {
            telemetry.addData("imu", "NOT FOUND in the configuration");
        } else {
            if (gamepad1.x) imu.resetYaw();
            telemetry.addData("Heading", "%.1f deg   (X = reset; turning LEFT should count UP)",
                imu.getRobotYawPitchRollAngles().getYaw(AngleUnit.DEGREES));
        }
        for (int i = 0; i < ENCODERS.length; i++) {
            if (motors[i] != null) telemetry.addData(ENCODERS[i] + " encoder", motors[i].getCurrentPosition());
            else if (i < 4) telemetry.addData(ENCODERS[i], "NOT FOUND in the configuration");
        }
    }
}
