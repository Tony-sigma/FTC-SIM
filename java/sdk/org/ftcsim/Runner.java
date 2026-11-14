package org.ftcsim;

import com.qualcomm.robotcore.eventloop.opmode.*;
import com.qualcomm.robotcore.hardware.HardwareMap;
import java.io.File;
import java.util.*;

/**
 * Finds the OpModes in the compiled TeamCode (by their @TeleOp / @Autonomous annotations) and runs one
 * against the simulator with the usual life cycle: init, wait for start, run, stop.
 *   Runner <build dir> --list
 *   Runner <build dir> <OpMode name or class> <port>
 */
public class Runner {
    static class Found { String name; String flavor; Class<?> type; }

    public static void main(String[] args) throws Exception {
        File build = new File(args[0]);
        List<Found> all = scan(build, build, new ArrayList<Found>());
        if (args.length < 2 || args[1].equals("--list")) {
            for (Found f : all) System.out.println("OPMODE\t" + f.flavor + "\t" + f.name + "\t" + f.type.getName());
            return;
        }
        Found pick = null;
        for (Found f : all) if (f.name.equalsIgnoreCase(args[1]) || f.type.getSimpleName().equalsIgnoreCase(args[1])) pick = f;
        if (pick == null) {
            System.out.println("ERROR: no OpMode called \"" + args[1] + "\". Found:");
            for (Found f : all) System.out.println("  " + f.name + "  (" + f.flavor + ")");
            System.exit(3);
        }
        int port = args.length > 2 ? Integer.parseInt(args[2]) : 7778;
        SimLink link = new SimLink(port);
        link.describe(pick.name, pick.flavor);
        System.out.println("RUNNING " + pick.name);
        int code = run(pick, link);
        link.stopAllMotors();
        link.setPhase(code == 0 ? "done" : "error");
        link.send();
        Thread.sleep(150);
        link.close();
        System.exit(code);
    }

    static int run(Found pick, final SimLink link) {
        final SimTelemetry telemetry = new SimTelemetry(link);
        try {
            final OpMode op = (OpMode) pick.type.getDeclaredConstructor().newInstance();
            op.internalSimLink = link;
            op.hardwareMap = new HardwareMap(link);
            op.gamepad1 = link.gamepad1;
            op.gamepad2 = link.gamepad2;
            op.telemetry = telemetry;
            link.setPhase("init");
            if (op instanceof LinearOpMode) {
                final Throwable[] failure = {null};
                Thread t = new Thread(new Runnable() { public void run() {
                    try { ((LinearOpMode) op).runOpMode(); }
                    catch (InterruptedException | OpModeStopped e) { /* normal stop */ }
                    catch (Throwable e) { failure[0] = e; }
                } }, "opmode");
                t.start();
                boolean running = false;
                while (t.isAlive() && !link.isStopRequested()) {
                    if (!running && link.isStarted()) { running = true; link.setPhase("run"); op.resetRuntime(); }
                    link.waitForPacket();
                }
                // Give the OpMode a moment to notice opModeIsActive() == false, then insist.
                t.join(1000);
                if (t.isAlive()) { t.interrupt(); t.join(1000); }
                if (failure[0] != null) throw failure[0];
            } else {
                op.init();
                telemetry.update();
                while (!link.isStarted() && !link.isStopRequested()) {
                    op.time = op.getRuntime();
                    op.init_loop();
                    telemetry.update();
                    link.waitForPacket();
                }
                if (!link.isStopRequested()) {
                    link.setPhase("run");
                    op.resetRuntime();
                    op.start();
                    while (!link.isStopRequested()) {
                        op.time = op.getRuntime();
                        op.loop();
                        telemetry.update();
                        link.waitForPacket();
                    }
                }
                op.stop();
            }
            return 0;
        } catch (OpModeStopped e) {
            return 0;
        } catch (Throwable e) {
            Throwable cause = e instanceof java.lang.reflect.InvocationTargetException && e.getCause() != null ? e.getCause() : e;
            System.out.println("OPMODE CRASHED: " + cause);
            for (StackTraceElement el : cause.getStackTrace()) {
                if (el.getClassName().startsWith("org.ftcsim.Runner")) break;
                System.out.println("    at " + el);
            }
            link.setTelemetry("OpMode crashed:\n" + cause);
            return 1;
        }
    }

    static List<Found> scan(File root, File dir, List<Found> out) {
        File[] files = dir.listFiles();
        if (files == null) return out;
        Arrays.sort(files);
        for (File f : files) {
            if (f.isDirectory()) { scan(root, f, out); continue; }
            String path = root.toURI().relativize(f.toURI()).getPath();
            if (!path.endsWith(".class") || path.contains("$") || path.startsWith("org/ftcsim/") || path.startsWith("com/qualcomm/")) continue;
            try {
                Class<?> c = Class.forName(path.substring(0, path.length() - 6).replace('/', '.'), false, Thread.currentThread().getContextClassLoader());
                if (!OpMode.class.isAssignableFrom(c) || java.lang.reflect.Modifier.isAbstract(c.getModifiers()) || c.isAnnotationPresent(Disabled.class)) continue;
                Found found = new Found();
                found.type = c;
                TeleOp tele = c.getAnnotation(TeleOp.class);
                Autonomous auto = c.getAnnotation(Autonomous.class);
                if (tele != null) { found.flavor = "teleop"; found.name = tele.name(); }
                else if (auto != null) { found.flavor = "auto"; found.name = auto.name(); }
                else continue;
                if (found.name.isEmpty()) found.name = c.getSimpleName();
                out.add(found);
            } catch (Throwable ignored) { }
        }
        return out;
    }
}
