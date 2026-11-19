package org.ftcsim;
import org.firstinspires.ftc.robotcore.external.hardware.camera.WebcamName;
/** The simulated USB camera. Hand it to VisionPortal.Builder.setCamera(), as on the real robot. */
public class SimWebcam implements WebcamName {
    public final SimLink link;
    public final String name;
    public SimWebcam(SimLink link, String name) { this.link = link; this.name = name; }
    @Override public String getDeviceName() { return "Simulated webcam " + name; }
}
