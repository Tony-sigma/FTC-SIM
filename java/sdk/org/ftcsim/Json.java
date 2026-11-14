package org.ftcsim;

import java.util.*;

/** Tiny JSON reader/writer: enough for the simulator link, no libraries needed. */
public final class Json {
    private final String s;
    private int i = 0;
    private Json(String s) { this.s = s; }

    public static Object parse(String text) { return new Json(text).value(); }

    @SuppressWarnings("unchecked")
    public static Map<String, Object> object(Object o) { return o instanceof Map ? (Map<String, Object>) o : new HashMap<String, Object>(); }
    @SuppressWarnings("unchecked")
    public static List<Object> list(Object o) { return o instanceof List ? (List<Object>) o : new ArrayList<Object>(); }
    public static double num(Object o) { return o instanceof Number ? ((Number) o).doubleValue() : 0.0; }
    public static boolean bool(Object o) { return o instanceof Boolean && (Boolean) o; }

    private void ws() { while (i < s.length() && Character.isWhitespace(s.charAt(i))) i++; }

    private Object value() {
        ws();
        if (i >= s.length()) return null;
        char c = s.charAt(i);
        if (c == '{') {
            Map<String, Object> m = new LinkedHashMap<>();
            i++; ws();
            if (s.charAt(i) == '}') { i++; return m; }
            while (true) {
                ws(); String k = string(); ws(); i++; // ':'
                m.put(k, value()); ws();
                if (s.charAt(i++) == '}') return m;
            }
        }
        if (c == '[') {
            List<Object> l = new ArrayList<>();
            i++; ws();
            if (s.charAt(i) == ']') { i++; return l; }
            while (true) {
                l.add(value()); ws();
                if (s.charAt(i++) == ']') return l;
            }
        }
        if (c == '"') return string();
        if (s.startsWith("true", i)) { i += 4; return Boolean.TRUE; }
        if (s.startsWith("false", i)) { i += 5; return Boolean.FALSE; }
        if (s.startsWith("null", i)) { i += 4; return null; }
        int st = i;
        while (i < s.length() && "+-0123456789.eE".indexOf(s.charAt(i)) >= 0) i++;
        return Double.parseDouble(s.substring(st, i));
    }

    private String string() {
        StringBuilder b = new StringBuilder();
        i++; // opening quote
        while (s.charAt(i) != '"') {
            char c = s.charAt(i++);
            if (c == '\\') {
                char e = s.charAt(i++);
                switch (e) {
                    case 'n': b.append('\n'); break;
                    case 't': b.append('\t'); break;
                    case 'r': b.append('\r'); break;
                    case 'u': b.append((char) Integer.parseInt(s.substring(i, i + 4), 16)); i += 4; break;
                    default: b.append(e);
                }
            } else b.append(c);
        }
        i++;
        return b.toString();
    }

    public static String quote(String v) {
        StringBuilder b = new StringBuilder("\"");
        for (char c : v.toCharArray()) {
            if (c == '"' || c == '\\') b.append('\\').append(c);
            else if (c == '\n') b.append("\\n");
            else if (c < 0x20) b.append(' ');
            else b.append(c);
        }
        return b.append('"').toString();
    }
}
