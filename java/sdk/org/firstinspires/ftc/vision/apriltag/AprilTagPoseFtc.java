package org.firstinspires.ftc.vision.apriltag;
/**
 * Where a tag is, seen from the camera: x = to the right, y = straight out of the lens, z = up.
 * range = distance along the floor of the camera's view, bearing = how far the camera would have to
 * turn to face the tag (positive = turn LEFT), elevation = how far it would have to tilt up.
 * roll = how the tags are turned in the picture: between -90 and 90 means right way up.
 * In the simulator yaw and pitch are always 0.
 */
public class AprilTagPoseFtc {
    public final double x, y, z, yaw, pitch, roll, range, bearing, elevation;
    public AprilTagPoseFtc(double x, double y, double z, double yaw, double pitch, double roll, double range, double bearing, double elevation) {
        this.x = x; this.y = y; this.z = z; this.yaw = yaw; this.pitch = pitch; this.roll = roll;
        this.range = range; this.bearing = bearing; this.elevation = elevation;
    }
}
