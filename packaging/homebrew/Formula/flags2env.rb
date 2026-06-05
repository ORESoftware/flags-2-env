class Flags2env < Formula
  desc "Parse project-declared CLI flags into environment override maps"
  homepage "https://github.com/ORESoftware/flags-2-env"
  url "https://github.com/ORESoftware/flags-2-env.git", tag: "v0.1.0"
  version "0.1.0"
  license "MIT"
  head "https://github.com/ORESoftware/flags-2-env.git", branch: "main"

  depends_on "gcc" => :build

  def install
    system "make", "all"

    bin.install "build/flags2env"
    include.install "src/parser.h" => "flags2env/parser.h"
    lib.install "build/libflags2env.a"
    if OS.mac?
      lib.install "build/libflags2env.dylib"
    else
      lib.install "build/libflags2env.so"
    end

    (pkgshare/"shell").install "clients/bash/flags2env.bash"
    (pkgshare/"shell").install "clients/zsh/flags2env.zsh"
  end

  def caveats
    <<~EOS
      Bash integration:
        source "#{opt_pkgshare}/shell/flags2env.bash"

      Zsh integration:
        source "#{opt_pkgshare}/shell/flags2env.zsh"
    EOS
  end

  test do
    (testpath/".cli-flags.toml").write <<~TOML
      [flags.port]
      env = "PORT"
      aliases = ["port"]
      type = "integer"

      [flags.debug]
      env = "DEBUG"
      aliases = ["debug"]
      type = "bool"
    TOML

    assert_match "\"PORT\":\"8181\"", shell_output("#{bin}/flags2env --port 8181")
    assert_match "export DEBUG='true'", shell_output("#{bin}/flags2env shell-env -- --debug")

    assert_path_exists pkgshare/"shell/flags2env.bash"
    assert_path_exists pkgshare/"shell/flags2env.zsh"

    (testpath/"bash-helper-test").write <<~SH
      #!/usr/bin/env bash
      set -euo pipefail
      source "#{pkgshare}/shell/flags2env.bash"
      export FLAGS2ENV_BIN="#{bin}/flags2env"
      export FLAGS2ENV_CONFIG="#{testpath}/.cli-flags.toml"
      flags2env_apply --debug
      printf "%s" "$DEBUG"
    SH

    assert_equal "true", shell_output("bash #{testpath}/bash-helper-test")

    if File.exist?("/bin/zsh")
      (testpath/"zsh-helper-test").write <<~SH
        #!/usr/bin/env zsh
        set -euo pipefail
        source "#{pkgshare}/shell/flags2env.zsh"
        export FLAGS2ENV_BIN="#{bin}/flags2env"
        export FLAGS2ENV_CONFIG="#{testpath}/.cli-flags.toml"
        flags2env_apply --debug
        printf "%s" "$DEBUG"
      SH

      assert_equal "true", shell_output("/bin/zsh #{testpath}/zsh-helper-test")
    end
  end
end
