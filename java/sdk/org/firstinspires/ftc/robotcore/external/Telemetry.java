package org.firstinspires.ftc.robotcore.external;
public interface Telemetry {
    interface Item { Item setValue(Object value); Item setValue(String format, Object... args); Item setCaption(String caption); Item setRetained(Boolean retained); }
    interface Line { }
    Item addData(String caption, Object value);
    Item addData(String caption, String format, Object... args);
    Line addLine();
    Line addLine(String lineCaption);
    void clear();
    void clearAll();
    boolean update();
    void setAutoClear(boolean autoClear);
    boolean isAutoClear();
    default void speak(String text) { }
    default void setMsTransmissionInterval(int ms) { }
    default int getMsTransmissionInterval() { return 250; }
}
