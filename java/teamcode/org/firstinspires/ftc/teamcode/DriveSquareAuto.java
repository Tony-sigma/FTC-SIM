package org.firstinspires.ftc.teamcode;

import com.qualcomm.robotcore.eventloop.opmode.Autonomous;
import com.qualcomm.robotcore.eventloop.opmode.LinearOpMode;
import com.qualcomm.robotcore.hardware.DcMotor;
import com.qualcomm.robotcore.hardware.DcMotorSimple;
import com.qualcomm.robotcore.hardware.IMU;
import org.firstinspires.ftc.robotcore.external.navigation.AngleUnit;

/**
 * Sample autonomous: drive forward 24 inches using the wheel encoders, then turn 90 degrees left
 * using the IMU. Ordinary FTC code; runs on the Control Hub and in the simulator.
 */
@Autonomous(name = "Drive And Turn", group = "Biobuzz")
public class DriveSquareAuto extends LinearOpMode {
    static final double TICKS_PER_REV = 537.7;
    static final double WHEEL_DIAMETER_IN = 104.0 / 25.4;
    static final double TICKS_PER_INCH = TICKS_PER_REV / (Math.PI * WHEEL_DIAMETER_IN);

    private DcMotor frontLeft, frontRight, backLeft, backRight;
    private IMU imu;

    @Override
    public void runOpMode() {
        frontLeft = hardwareMap.get(DcMotor.class, "frontLeft");
        frontRight = hardwareMap.get(DcMotor.class, "frontRight");
        backLeft = hardwareMap.get(DcMotor.class, "backLeft");
        backRight = hardwareMap.get(DcMotor.class, "backRight");
        frontLeft.setDirection(DcMotorSimple.Direction.REVERSE);
        backLeft.setDirection(DcMotorSimple.Direction.REVERSE);
        imu = hardwareMap.get(IMU.class, "imu");
        imu.resetYaw();

        telemetry.addData("Status", "Ready");
        telemetry.update();
        waitForStart();

        driveForward(24.0, 0.5);
        turnTo(90.0, 0.4);

        telemetry.addData("Status", "Done");
        telemetry.update();
        sleep(500);
    }

    private void driveForward(double inches, double power) {
        int target = (int) Math.round(inches * TICKS_PER_INCH);
        for (DcMotor m : new DcMotor[]{frontLeft, frontRight, backLeft, backRight}) {
            m.setMode(DcMotor.RunMode.STOP_AND_RESET_ENCODER);
            m.setTargetPosition(target);
            m.setMode(DcMotor.RunMode.RUN_TO_POSITION);
            m.setPower(power);
        }
        while (opModeIsActive() && (frontLeft.isBusy() || frontRight.isBusy())) {
            telemetry.addData("Driving", "%d / %d ticks", frontLeft.getCurrentPosition(), target);
            telemetry.update();
        }
        for (DcMotor m : new DcMotor[]{frontLeft, frontRight, backLeft, backRight}) {
            m.setPower(0);
            m.setMode(DcMotor.RunMode.RUN_USING_ENCODER);
        }
    }

    private void turnTo(double degrees, double maxPower) {
        while (opModeIsActive()) {
            double error = AngleUnit.normalizeDegrees(degrees - imu.getRobotYawPitchRollAngles().getYaw(AngleUnit.DEGREES));
            if (Math.abs(error) < 1.0) break;
            double power = Math.max(-maxPower, Math.min(maxPower, error * 0.02));
            if (Math.abs(power) < 0.08) power = Math.signum(power) * 0.08;
            frontLeft.setPower(-power);   // left side backwards, right side forwards = turn left
            backLeft.setPower(-power);
            frontRight.setPower(power);
            backRight.setPower(power);
            telemetry.addData("Turning", "%.1f deg to go", error);
            telemetry.update();
        }
        frontLeft.setPower(0);
        backLeft.setPower(0);
        frontRight.setPower(0);
        backRight.setPower(0);
    }
}
