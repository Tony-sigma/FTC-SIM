package org.ftcsim;

import org.firstinspires.ftc.robotcore.external.Telemetry;
import java.util.ArrayList;
import java.util.List;

public class SimTelemetry implements Telemetry {
    private final SimLink link;
    private final List<String[]> lines = new ArrayList<>();
    private boolean autoClear = true;
    public SimTelemetry(SimLink link) { this.link = link; }

    private class ItemImpl implements Item, Line {
        final String[] row;
        ItemImpl(String[] row) { this.row = row; }
        public Item setValue(Object value) { row[1] = String.valueOf(value); return this; }
        public Item setValue(String format, Object... args) { row[1] = String.format(format, args); return this; }
        public Item setCaption(String caption) { row[0] = caption; return this; }
        public Item setRetained(Boolean retained) { return this; }
    }
    private synchronized ItemImpl add(String caption, String value) {
        String[] row = {caption, value};
        lines.add(row);
        return new ItemImpl(row);
    }
    @Override public Item addData(String caption, Object value) { return add(caption, String.valueOf(value)); }
    @Override public Item addData(String caption, String format, Object... args) { return add(caption, String.format(format, args)); }
    @Override public Line addLine() { return add("", null); }
    @Override public Line addLine(String lineCaption) { return add(lineCaption, null); }
    @Override public synchronized void clear() { lines.clear(); }
    @Override public synchronized void clearAll() { lines.clear(); }
    @Override public synchronized boolean update() {
        StringBuilder b = new StringBuilder();
        for (String[] row : lines) b.append(row[1] == null ? row[0] : row[0] + " : " + row[1]).append('\n');
        link.setTelemetry(b.toString());
        if (autoClear) lines.clear();
        return true;
    }
    @Override public void setAutoClear(boolean a) { autoClear = a; }
    @Override public boolean isAutoClear() { return autoClear; }
}
