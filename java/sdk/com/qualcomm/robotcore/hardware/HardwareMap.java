package com.qualcomm.robotcore.hardware;

import java.util.*;

/** Hands out simulated devices by the names in the simulator's robot_config.json. */
public class HardwareMap {
    private final org.ftcsim.SimLink link;
    private final Map<String, Object> devices = new HashMap<>();
    public final DeviceMapping<DcMotor> dcMotor = new DeviceMapping<>(DcMotor.class);
    public final DeviceMapping<Servo> servo = new DeviceMapping<>(Servo.class);
    public final DeviceMapping<CRServo> crservo = new DeviceMapping<>(CRServo.class);

    public HardwareMap(org.ftcsim.SimLink link) { this.link = link; }

    public class DeviceMapping<T> {
        private final Class<T> type;
        DeviceMapping(Class<T> type) { this.type = type; }
        public T get(String name) { return HardwareMap.this.get(type, name); }
        public boolean contains(String name) { return tryGet(type, name) != null; }
    }

    public <T> T get(Class<? extends T> type, String name) {
        T dev = tryGet(type, name);
        if (dev == null) {
            throw new IllegalArgumentException("Unable to find a hardware device with name \"" + name + "\" and type "
                + type.getSimpleName() + ". The simulated robot has motors " + link.motorNames() + ", servos "
                + link.servoNames() + " and an IMU (any name). Names come from robot_config.json.");
        }
        return dev;
    }

    public <T> T tryGet(Class<? extends T> type, String name) {
        Object dev = devices.get(name);
        if (dev == null) {
            if (type == IMU.class) dev = new org.ftcsim.SimIMU(link);
            else if (type.isAssignableFrom(org.ftcsim.SimMotor.class) && link.motorNames().contains(name)) dev = new org.ftcsim.SimMotor(link, name);
            else if (type.isAssignableFrom(org.ftcsim.SimServo.class) && link.servoNames().contains(name)) dev = new org.ftcsim.SimServo(link, name);
            if (dev != null) devices.put(name, dev);
        }
        return type.isInstance(dev) ? type.cast(dev) : null;
    }

    public <T> List<T> getAll(Class<? extends T> type) {
        List<T> out = new ArrayList<>();
        for (Object d : devices.values()) if (type.isInstance(d)) out.add(type.cast(d));
        return out;
    }
}
