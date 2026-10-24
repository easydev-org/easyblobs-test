package dev.easyblobs.test.gradle;

/** A real class the compiler must accept. */
public final class Greeter {
    private Greeter() {}

    public static String greet(String name) {
        return "hello " + name;
    }
}
