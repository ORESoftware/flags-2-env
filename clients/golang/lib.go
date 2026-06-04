package flags2env

/*
#cgo CFLAGS: -I.
#include "parser.h"
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"unsafe"
)

func Parse(argv []string) (map[string]string, error) {
	encoded, err := json.Marshal(argv)
	if err != nil {
		return nil, err
	}

	cArgv := C.CString(string(encoded))
	defer C.free(unsafe.Pointer(cArgv))

	result := C.f2e_parse_json_argv(cArgv)
	if result == nil {
		return map[string]string{}, nil
	}
	defer C.f2e_free(result)

	var out map[string]string
	if err := json.Unmarshal([]byte(C.GoString(result)), &out); err != nil {
		return nil, err
	}
	return out, nil
}

func ParseProcess() (map[string]string, error) {
	result := C.f2e_parse_process()
	if result == nil {
		return map[string]string{}, nil
	}
	defer C.f2e_free(result)

	var out map[string]string
	if err := json.Unmarshal([]byte(C.GoString(result)), &out); err != nil {
		return nil, err
	}
	return out, nil
}

func ParseProcessFromFile(configPath string) (map[string]string, error) {
	cConfigPath := C.CString(configPath)
	defer C.free(unsafe.Pointer(cConfigPath))

	result := C.f2e_parse_process_from_file(cConfigPath)
	if result == nil {
		return map[string]string{}, nil
	}
	defer C.f2e_free(result)

	var out map[string]string
	if err := json.Unmarshal([]byte(C.GoString(result)), &out); err != nil {
		return nil, err
	}
	return out, nil
}

func ParseFromFile(configPath string, argv []string) (map[string]string, error) {
	encoded, err := json.Marshal(argv)
	if err != nil {
		return nil, err
	}

	cConfigPath := C.CString(configPath)
	cArgv := C.CString(string(encoded))
	defer C.free(unsafe.Pointer(cConfigPath))
	defer C.free(unsafe.Pointer(cArgv))

	result := C.f2e_parse_json_argv_from_file(cConfigPath, cArgv)
	if result == nil {
		return map[string]string{}, nil
	}
	defer C.f2e_free(result)

	var out map[string]string
	if err := json.Unmarshal([]byte(C.GoString(result)), &out); err != nil {
		return nil, err
	}
	return out, nil
}

func Apply(target map[string]string, argv []string) (map[string]string, error) {
	parsed, err := Parse(argv)
	if err != nil {
		return nil, err
	}
	if target == nil {
		target = map[string]string{}
	}
	for key, value := range parsed {
		target[key] = value
	}
	return target, nil
}

func ApplyProcess(target map[string]string) (map[string]string, error) {
	parsed, err := ParseProcess()
	if err != nil {
		return nil, err
	}
	if target == nil {
		target = map[string]string{}
	}
	for key, value := range parsed {
		target[key] = value
	}
	return target, nil
}
