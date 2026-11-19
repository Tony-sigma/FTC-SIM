package org.firstinspires.ftc.vision;

import android.util.Size;
import java.util.*;
import org.firstinspires.ftc.robotcore.external.hardware.camera.CameraName;
import org.firstinspires.ftc.vision.apriltag.AprilTagProcessor;

/** Simulator stand-in for the FTC SDK VisionPortal: connects a camera to its processors. */
public class VisionPortal {
    public enum CameraState { OPENING_CAMERA_DEVICE, CAMERA_DEVICE_READY, STARTING_STREAM, STREAMING, STOPPING_STREAM, CLOSING_CAMERA_DEVICE, CAMERA_DEVICE_CLOSED, ERROR }
    public enum StreamFormat { YUY2, MJPEG }
    public enum MultiPortalLayout { VERTICAL, HORIZONTAL }

    private final Map<VisionProcessor, Boolean> processors = new LinkedHashMap<>();
    private boolean streaming = true, closed = false;

    public static class Builder {
        private CameraName camera;
        private final List<VisionProcessor> list = new ArrayList<>();
        public Builder setCamera(CameraName camera) { this.camera = camera; return this; }
        public Builder addProcessor(VisionProcessor p) { list.add(p); return this; }
        public Builder addProcessors(VisionProcessor... ps) { list.addAll(Arrays.asList(ps)); return this; }
        public Builder setCameraResolution(Size size) { return this; }
        public Builder setStreamFormat(StreamFormat format) { return this; }
        public Builder enableLiveView(boolean enable) { return this; }
        public Builder setAutoStopLiveView(boolean auto) { return this; }
        public Builder setAutoStartStreamOnBuild(boolean auto) { return this; }
        public Builder setLiveViewContainerId(int id) { return this; }
        public Builder setShowStatsOverlay(boolean show) { return this; }
        public VisionPortal build() {
            if (camera == null) throw new RuntimeException("You can't build a vision portal without setting a camera!");
            if (!(camera instanceof org.ftcsim.SimWebcam))
                throw new RuntimeException("The simulator only has the webcam from hardwareMap.get(WebcamName.class, ...).");
            VisionPortal portal = new VisionPortal();
            for (VisionProcessor p : list) {
                portal.processors.put(p, true);
                if (p instanceof AprilTagProcessor) ((AprilTagProcessor) p).internalAttach(portal, ((org.ftcsim.SimWebcam) camera).link);
            }
            return portal;
        }
    }

    public static VisionPortal easyCreateWithDefaults(CameraName camera, VisionProcessor... processors) {
        return new Builder().setCamera(camera).addProcessors(processors).build();
    }
    public static int[] makeMultiPortalView(int numPortals, MultiPortalLayout layout) { return new int[numPortals]; }

    public CameraState getCameraState() { return closed ? CameraState.CAMERA_DEVICE_CLOSED : (streaming ? CameraState.STREAMING : CameraState.CAMERA_DEVICE_READY); }
    public void stopStreaming() { streaming = false; }
    public void resumeStreaming() { if (!closed) streaming = true; }
    public void stopLiveView() { }
    public void resumeLiveView() { }
    public void setProcessorEnabled(VisionProcessor p, boolean enabled) { if (processors.containsKey(p)) processors.put(p, enabled); }
    public boolean getProcessorEnabled(VisionProcessor p) { return Boolean.TRUE.equals(processors.get(p)); }
    public float getFps() { return streaming ? 30f : 0f; }
    public void close() { closed = true; streaming = false; }
    /** True while frames are flowing to this processor. Simulator plumbing. */
    public boolean internalIsLive(VisionProcessor p) { return streaming && !closed && getProcessorEnabled(p); }
}
