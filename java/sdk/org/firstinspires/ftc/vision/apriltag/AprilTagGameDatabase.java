package org.firstinspires.ftc.vision.apriltag;
/** In the simulator every tag on the field counts as known, so this library is empty on purpose. */
public class AprilTagGameDatabase {
    public static AprilTagLibrary getCurrentGameTagLibrary() { return new AprilTagLibrary.Builder().build(); }
}
