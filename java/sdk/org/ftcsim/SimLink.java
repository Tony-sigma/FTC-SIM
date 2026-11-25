package org.ftcsim;

import com.qualcomm.robotcore.hardware.Gamepad;
import java.io.*;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * The wire between the OpMode and the Godot simulator: one line of JSON each way, about 60 times a
 * second. The simulator sends sensors and gamepads; we answer with motor powers and servo positions.
 */
public class SimLink {
    private final Socket socket;
    private final BufferedReader in;
    private final Writer out;
    private final Object packetLock = new Object();
    private long packets = 0;

    private volatile Map<String, Object> motorsIn = new HashMap<>();
    private volatile double yawDeg = 0, yawRateDeg = 0, simTime = 0;
    private volatile boolean started = false, stopRequested = false, connected = true;
    private Map<String, Double> motorMaxTps = new HashMap<>();
    private List<String> servoNames = new ArrayList<>();
    private volatile boolean helloSeen = false;
    private volatile List<double[]> camTags = new ArrayList<>();
    private volatile List<String> camNames = new ArrayList<>();
    private volatile double[] camPose = {0, 0, 0};
    private volatile String cameraName = "Webcam 1";

    private final Map<String, Double> motorsOut = new ConcurrentHashMap<>();
    private final Map<String, Double> servosOut = new ConcurrentHashMap<>();
    /** Motors whose speed the controller holds (RUN_USING_ENCODER / setVelocity), as on the real hub. */
    private final Set<String> heldOut = ConcurrentHashMap.newKeySet();
    private final List<SimMotor> motors = Collections.synchronizedList(new ArrayList<SimMotor>());
    private volatile String telemetry = "";
    private volatile String opmode = "", flavor = "", phase = "connecting";
    public final Gamepad gamepad1 = new Gamepad(), gamepad2 = new Gamepad();

    public SimLink(int port) throws IOException {
        Socket s = null;
        IOException last = null;
        for (int attempt = 0; attempt < 40 && s == null; attempt++) {
            try { s = new Socket("127.0.0.1", port); }
            catch (IOException e) { last = e; try { Thread.sleep(250); } catch (InterruptedException ie) { break; } }
        }
        if (s == null) throw new IOException("Could not reach the simulator on port " + port + ". Is it running? (" + last + ")");
        socket = s;
        socket.setTcpNoDelay(true);
        in = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8));
        out = new OutputStreamWriter(socket.getOutputStream(), StandardCharsets.UTF_8);
        Thread t = new Thread(this::readLoop, "sim-link");
        t.setDaemon(true);
        t.start();
        long deadline = System.currentTimeMillis() + 5000;
        while (!helloSeen && connected && System.currentTimeMillis() < deadline) waitForPacket();
        if (!helloSeen) throw new IOException("The simulator did not describe its robot in time.");
    }

    private void readLoop() {
        try {
            String line;
            while ((line = in.readLine()) != null) {
                Map<String, Object> m = Json.object(Json.parse(line));
                if ("hello".equals(m.get("type"))) {
                    Map<String, Double> max = new LinkedHashMap<>();
                    for (Map.Entry<String, Object> e : Json.object(m.get("motors")).entrySet()) max.put(e.getKey(), Json.num(e.getValue()));
                    List<String> servos = new ArrayList<>();
                    for (Object o : Json.list(m.get("servos"))) servos.add(String.valueOf(o));
                    motorMaxTps = max;
                    if (m.get("camera") != null) cameraName = String.valueOf(m.get("camera"));
                    servoNames = servos;
                    helloSeen = true;
                } else {
                    motorsIn = Json.object(m.get("motors"));
                    List<Object> imu = Json.list(m.get("imu"));
                    if (imu.size() >= 2) { yawDeg = Json.num(imu.get(0)); yawRateDeg = Json.num(imu.get(1)); }
                    simTime = Json.num(m.get("t"));
                    List<double[]> tags = new ArrayList<>();
                    List<String> tagNames = new ArrayList<>();
                    for (Object o : Json.list(m.get("tags"))) {
                        List<Object> t = Json.list(o);
                        if (t.size() >= 6) {
                            double[] row = new double[5];
                            for (int k = 0; k < 5; k++) row[k] = Json.num(t.get(k + 1));
                            tags.add(row);
                            tagNames.add(String.valueOf(t.get(0)));
                        }
                    }
                    camNames = tagNames;
                    camTags = tags;
                    List<Object> cp = Json.list(m.get("campose"));
                    if (cp.size() >= 3) camPose = new double[]{Json.num(cp.get(0)), Json.num(cp.get(1)), Json.num(cp.get(2))};
                    if (Json.bool(m.get("start"))) started = true;
                    if (Json.bool(m.get("stop"))) stopRequested = true;
                    fill(gamepad1, Json.object(m.get("gamepad1")));
                    fill(gamepad2, Json.object(m.get("gamepad2")));
                    send();
                }
                synchronized (packetLock) { packets++; packetLock.notifyAll(); }
            }
        } catch (IOException | RuntimeException e) {
            // the simulator went away
        }
        connected = false;
        stopRequested = true;
        synchronized (packetLock) { packets++; packetLock.notifyAll(); }
    }

    private static void fill(Gamepad g, Map<String, Object> m) {
        g.left_stick_x = (float) Json.num(m.get("lx"));
        g.left_stick_y = (float) Json.num(m.get("ly"));
        g.right_stick_x = (float) Json.num(m.get("rx"));
        g.right_stick_y = (float) Json.num(m.get("ry"));
        g.left_trigger = (float) Json.num(m.get("lt"));
        g.right_trigger = (float) Json.num(m.get("rt"));
        Set<Object> b = new HashSet<>(Json.list(m.get("b")));
        g.a = g.cross = b.contains("a");
        g.b = g.circle = b.contains("b");
        g.x = g.square = b.contains("x");
        g.y = g.triangle = b.contains("y");
        g.dpad_up = b.contains("dpad_up");
        g.dpad_down = b.contains("dpad_down");
        g.dpad_left = b.contains("dpad_left");
        g.dpad_right = b.contains("dpad_right");
        g.left_bumper = b.contains("left_bumper");
        g.right_bumper = b.contains("right_bumper");
        g.left_stick_button = b.contains("left_stick_button");
        g.right_stick_button = b.contains("right_stick_button");
        g.start = g.options = b.contains("start");
        g.back = g.share = b.contains("back");
        g.guide = g.ps = b.contains("guide");
    }

    /** Send the current outputs. Called for every packet from the simulator, and when the OpMode ends. */
    public synchronized void send() {
        synchronized (motors) { for (SimMotor m : motors) m.refresh(); }
        StringBuilder b = new StringBuilder(256);
        b.append("{\"opmode\":").append(Json.quote(opmode)).append(",\"flavor\":").append(Json.quote(flavor))
         .append(",\"phase\":").append(Json.quote(phase)).append(",\"motors\":{");
        boolean first = true;
        for (Map.Entry<String, Double> e : motorsOut.entrySet()) {
            if (!first) b.append(','); first = false;
            b.append(Json.quote(e.getKey())).append(':').append(e.getValue());
        }
        b.append("},\"servos\":{");
        first = true;
        for (Map.Entry<String, Double> e : servosOut.entrySet()) {
            if (!first) b.append(','); first = false;
            b.append(Json.quote(e.getKey())).append(':').append(e.getValue());
        }
        b.append("},\"held\":[");
        first = true;
        for (String name : heldOut) {
            if (!first) b.append(','); first = false;
            b.append(Json.quote(name));
        }
        b.append("],\"telemetry\":").append(Json.quote(telemetry)).append("}\n");
        try { out.write(b.toString()); out.flush(); } catch (IOException e) { connected = false; stopRequested = true; }
    }

    /** Block until the simulator has sent fresh data (or half a second passes). */
    public void waitForPacket() {
        synchronized (packetLock) {
            long seen = packets;
            long deadline = System.currentTimeMillis() + 500;
            while (packets == seen && System.currentTimeMillis() < deadline) {
                try { packetLock.wait(50); } catch (InterruptedException e) { Thread.currentThread().interrupt(); return; }
            }
        }
    }

    public void describe(String opmode, String flavor) { this.opmode = opmode; this.flavor = flavor; }
    public void setPhase(String phase) { this.phase = phase; }
    public void setTelemetry(String text) { telemetry = text; }
    public boolean isStarted() { return started; }
    public boolean isStopRequested() { return stopRequested; }
    public boolean isConnected() { return connected; }
    public void requestStop() { stopRequested = true; }
    public double simTime() { return simTime; }
    public double yawDeg() { return yawDeg; }
    public double yawRateDeg() { return yawRateDeg; }
    /** AprilTag clusters the camera sees, biggest first: {percent found, x, y, z, roll}; x/y/z in inches in the camera frame. */
    public List<double[]> cameraTags() { return camTags; }
    public List<String> cameraClusterNames() { return camNames; }
    /** Robot pose worked out from the tags: {x m, y m, heading deg}. */
    public double[] cameraRobotPose() { return camPose; }
    public String cameraName() { return cameraName; }
    public long packetCount() { synchronized (packetLock) { return packets; } }
    public Set<String> motorNames() { return motorMaxTps.keySet(); }
    public List<String> servoNames() { return servoNames; }
    public double motorMaxTicksPerSecond(String name) { Double v = motorMaxTps.get(name); return v == null || v <= 0 ? 2800.0 : v; }
    /** Raw encoder count of a motor as the simulator reports it. */
    public double motorTicks(String name) { List<Object> v = Json.list(motorsIn.get(name)); return v.size() > 0 ? Json.num(v.get(0)) : 0.0; }
    public double motorTicksPerSecond(String name) { List<Object> v = Json.list(motorsIn.get(name)); return v.size() > 1 ? Json.num(v.get(1)) : 0.0; }
    void register(SimMotor m) { motors.add(m); }
    void setMotor(String name, double power) { motorsOut.put(name, power); }
    void setMotorHeld(String name, boolean held) { if (held) heldOut.add(name); else heldOut.remove(name); }
    void setServo(String name, double position) { servosOut.put(name, position); }
    /** Everything off: used when the OpMode stops, like the real robot controller does. */
    public void stopAllMotors() {
        synchronized (motors) { for (SimMotor m : motors) m.forceStop(); }
        for (String k : motorsOut.keySet()) motorsOut.put(k, 0.0);
    }
    public void close() { try { socket.close(); } catch (IOException ignored) { } }
}
