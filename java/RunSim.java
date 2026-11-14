import java.io.*;
import java.net.URL;
import java.net.URLClassLoader;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.stream.*;
import javax.tools.*;

/**
 * Compiles the simulator's stand-in FTC SDK plus your TeamCode, then runs one OpMode against the
 * simulator. Needs a JDK 11 or newer; nothing else to install.
 *
 *   java RunSim.java --list                      show the OpModes it can find
 *   java RunSim.java "My TeleOp"                 run one (by its annotation name or class name)
 *   java RunSim.java --check                     only compile, to see the errors
 * Options: --teamcode <folder>  --port <n>  --home <this java folder>  --log <file>
 *
 * A file that does not compile here (for example because it uses a library the simulator does not
 * have) is reported and left out, so the rest of your code still runs.
 */
public class RunSim {
    public static void main(String[] args) throws Exception {
        String home = "", teamcode = "", log = null, port = "7778";
        List<String> rest = new ArrayList<>();
        for (int i = 0; i < args.length; i++) {
            if (args[i].equals("--home") && i + 1 < args.length) home = args[++i];
            else if (args[i].equals("--teamcode") && i + 1 < args.length) teamcode = args[++i];
            else if (args[i].equals("--port") && i + 1 < args.length) port = args[++i];
            else if (args[i].equals("--log") && i + 1 < args.length) log = args[++i];
            else rest.add(args[i]);
        }
        if (log != null) {
            PrintStream ps = new PrintStream(new FileOutputStream(log), true, "UTF-8");
            System.setOut(ps);
            System.setErr(ps);
        }
        String what = rest.isEmpty() ? "--list" : rest.get(0);
        Path homeDir = Paths.get(home).toAbsolutePath();
        Path codeDir = teamcode.isEmpty() ? homeDir.resolve("teamcode") : Paths.get(teamcode).toAbsolutePath();
        Path build = homeDir.resolve("build");
        if (!Files.isDirectory(homeDir.resolve("sdk"))) fail("ERROR: " + homeDir + " has no sdk folder. Run this from the java folder, or pass --home.");
        if (!Files.isDirectory(codeDir)) fail("ERROR: TeamCode folder not found: " + codeDir);
        JavaCompiler javac = ToolProvider.getSystemJavaCompiler();
        if (javac == null) fail("ERROR: this Java has no compiler. Install a JDK (11 or newer), for example from https://adoptium.net");

        wipe(build);
        Files.createDirectories(build);
        System.out.println("COMPILING");
        if (!compile(javac, sources(homeDir.resolve("sdk")), build, null)) fail("ERROR: the simulator SDK itself did not compile.");
        List<Path> files = sources(codeDir);
        int excluded = 0;
        for (int pass = 0; pass < 12 && !files.isEmpty(); pass++) {
            Map<Path, List<String>> errors = new LinkedHashMap<>();
            if (compile(javac, files, build, errors)) break;
            if (errors.isEmpty()) fail("ERROR: compilation failed.");
            for (Map.Entry<Path, List<String>> e : errors.entrySet()) {
                System.out.println("EXCLUDED " + codeDir.relativize(e.getKey()).toString().replace('\\', '/'));
                for (String line : e.getValue().subList(0, Math.min(4, e.getValue().size()))) System.out.println("    " + line);
                files.remove(e.getKey());
                excluded++;
            }
        }
        System.out.println("COMPILED " + files.size() + " file(s)" + (excluded > 0 ? ", " + excluded + " left out because of errors" : ""));
        if (what.equals("--check")) return;

        URLClassLoader loader = new URLClassLoader(new URL[]{build.toUri().toURL()}, ClassLoader.getPlatformClassLoader());
        Thread.currentThread().setContextClassLoader(loader);
        String[] runnerArgs = what.equals("--list") ? new String[]{build.toString(), "--list"} : new String[]{build.toString(), what, port};
        try {
            loader.loadClass("org.ftcsim.Runner").getMethod("main", String[].class).invoke(null, (Object) runnerArgs);
        } catch (java.lang.reflect.InvocationTargetException e) {
            System.out.println("ERROR: " + e.getCause());
            System.exit(1);
        }
    }

    static void fail(String message) { System.out.println(message); System.exit(2); }

    /** Compile; on failure, fill `errors` with the messages per broken file (when it is not null). */
    static boolean compile(JavaCompiler javac, List<Path> files, Path out, Map<Path, List<String>> errors) throws IOException {
        if (files.isEmpty()) return true;
        DiagnosticCollector<JavaFileObject> diags = new DiagnosticCollector<>();
        try (StandardJavaFileManager fm = javac.getStandardFileManager(diags, null, StandardCharsets.UTF_8)) {
            List<String> opts = Arrays.asList("-cp", out.toString(), "-d", out.toString(), "-encoding", "UTF-8", "-nowarn", "-proc:none");
            boolean ok = javac.getTask(null, fm, diags, opts, null, fm.getJavaFileObjectsFromPaths(files)).call();
            for (Diagnostic<? extends JavaFileObject> d : diags.getDiagnostics()) {
                if (d.getKind() != Diagnostic.Kind.ERROR) continue;
                String text = "line " + d.getLineNumber() + ": " + d.getMessage(Locale.ENGLISH).split("\\R")[0];
                if (d.getSource() == null) { System.out.println(text); continue; }
                Path p = Paths.get(d.getSource().toUri());
                if (errors != null) errors.computeIfAbsent(p, k -> new ArrayList<>()).add(text);
                else System.out.println(p + " " + text);
            }
            return ok;
        }
    }

    static List<Path> sources(Path dir) throws IOException {
        try (Stream<Path> s = Files.walk(dir)) {
            return s.filter(p -> p.toString().endsWith(".java")).sorted().collect(Collectors.toCollection(ArrayList::new));
        }
    }

    static void wipe(Path dir) throws IOException {
        if (!Files.exists(dir)) return;
        try (Stream<Path> s = Files.walk(dir)) {
            for (Path p : (Iterable<Path>) s.sorted(Comparator.reverseOrder())::iterator) Files.delete(p);
        }
    }
}
