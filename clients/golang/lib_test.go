package flags2env

import (
	"os"
	"testing"
)

func TestParseFindsParentConfig(t *testing.T) {
	original, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(original)

	if err := os.Chdir("../../tests/fixtures/nested/deeper"); err != nil {
		t.Fatal(err)
	}

	parsed, err := Parse([]string{"app", "--debug=t", "--port", "8181"})
	if err != nil {
		t.Fatal(err)
	}
	if parsed["DEBUG"] != "true" || parsed["PORT"] != "8181" || parsed["COLOR"] != "true" {
		t.Fatalf("unexpected parsed map: %#v", parsed)
	}

	explicit, err := ParseFromFile("../../.cli-flags.toml", []string{"app", "--debug=f"})
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
