package flags2env

import (
	"os"
	"path/filepath"
	"testing"
)

const testConfig = `
[flags.port]
env = "PORT"
aliases = ["port", "listen-port"]
short = "p"
type = "integer"
default = 3000

[flags.debug]
env = "DEBUG"
aliases = ["debug"]
short = "d"
type = "bool"
default = "false"
true_aliases = ["t", "1"]
false_aliases = ["f", "0"]

[flags.color]
env = "COLOR"
aliases = ["color"]
short = "c"
type = "bool"
default = "true"
`

func TestParseFindsParentConfig(t *testing.T) {
	original, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(original)

	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, ".cli-flags.toml"), []byte(testConfig), 0o644); err != nil {
		t.Fatal(err)
	}
	nested := filepath.Join(root, "nested", "deeper")
	if err := os.MkdirAll(nested, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(nested); err != nil {
		t.Fatal(err)
	}

	parsed, err := Parse([]string{"app", "--debug=t", "--port", "8181"})
	if err != nil {
		t.Fatal(err)
	}
	if parsed["DEBUG"] != "true" || parsed["PORT"] != "8181" || parsed["COLOR"] != "true" {
		t.Fatalf("unexpected parsed map: %#v", parsed)
	}

	explicit, err := ParseFromFile(filepath.Join(root, ".cli-flags.toml"), []string{"app", "--debug=f"})
	if err != nil {
		t.Fatal(err)
	}
	if explicit["DEBUG"] != "false" || explicit["PORT"] != "3000" {
		t.Fatalf("unexpected explicit config map: %#v", explicit)
	}

	combined, err := Apply(map[string]string{"PORT": "env", "KEEP": "1"}, []string{"app", "--port", "8181"})
	if err != nil {
		t.Fatal(err)
	}
	if combined["PORT"] != "8181" || combined["KEEP"] != "1" || combined["COLOR"] != "true" {
		t.Fatalf("unexpected combined map: %#v", combined)
	}
}
