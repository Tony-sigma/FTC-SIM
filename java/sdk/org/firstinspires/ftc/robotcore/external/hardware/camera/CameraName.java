package org.firstinspires.ftc.robotcore.external.hardware.camera;
public interface CameraName {
    default boolean isWebcam() { return true; }
    default boolean isCameraDirection() { return false; }
    default boolean isSwitchable() { return false; }
    default boolean isUnknown() { return false; }
}
