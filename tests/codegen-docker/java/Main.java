import generated.CliStuff;

import java.util.List;
import java.util.Map;

public final class Main {
  public static void main(String[] args) {
    CliStuff config = new CliStuff(
        4242L,
        0.25,
        true,
        "matrix",
        List.of(1, "two"),
        Map.of("region", "test"),
        Map.of("enabled", true),
        "123");

    if (config.PORT() != 4242L
        || !"matrix".equals(config.NAME())
        || !"123".equals(config.UNTYPED())
        || !"test".equals(config.LABELS().get("region"))) {
      throw new IllegalStateException("generated Java config has unexpected values");
    }

    System.out.println("java generated interface passed");
  }
}
