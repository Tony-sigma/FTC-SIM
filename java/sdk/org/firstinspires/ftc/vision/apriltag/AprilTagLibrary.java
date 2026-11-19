package org.firstinspires.ftc.vision.apriltag;
import java.util.*;
import org.firstinspires.ftc.robotcore.external.navigation.DistanceUnit;
public class AprilTagLibrary {
    private final Map<Integer, AprilTagMetadata> tags = new LinkedHashMap<>();
    public static class Builder {
        private final AprilTagLibrary lib = new AprilTagLibrary();
        public Builder setAllowOverwrite(boolean allow) { return this; }
        public Builder addTag(AprilTagMetadata m) { lib.tags.put(m.id, m); return this; }
        public Builder addTag(int id, String name, double size, DistanceUnit unit) { return addTag(new AprilTagMetadata(id, name, size, unit)); }
        public Builder addTags(AprilTagLibrary other) { lib.tags.putAll(other.tags); return this; }
        public AprilTagLibrary build() { return lib; }
    }
    public AprilTagMetadata[] getAllTags() { return tags.values().toArray(new AprilTagMetadata[0]); }
    public AprilTagMetadata lookupTag(int id) { return tags.get(id); }
}
