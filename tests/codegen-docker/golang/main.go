package main

import (
	"encoding/json"
	"fmt"

	"example.com/flags2env/codegen-matrix/generated"
)

func main() {
	payload := []byte(`{
		"PORT": 4242,
		"RATIO": 0.25,
		"DEBUG": true,
		"NAME": "matrix",
		"ITEMS": [1, "two"],
		"LABELS": {"region": "test"},
		"PAYLOAD": {"enabled": true},
		"UNTYPED": "123"
	}`)

	var config generated.CliStuff
	if err := json.Unmarshal(payload, &config); err != nil {
		panic(err)
	}
	if config.PORT != 4242 || config.NAME == nil || *config.NAME != "matrix" {
		panic("generated Go config has unexpected values")
	}
	if config.UNTYPED != "123" || config.LABELS["region"] != "test" {
		panic("generated Go config lost string or map values")
	}

	fmt.Println("golang generated interface passed")
}
