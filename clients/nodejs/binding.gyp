{
  "targets": [
    {
      "target_name": "flags2env",
      "sources": [
        "addon.c",
        "../../src/parser.c"
      ],
      "include_dirs": [
        "../../src"
      ],
      "cflags": ["-std=c99"],
      "xcode_settings": {
        "OTHER_CFLAGS": ["-std=c99"]
      }
    }
  ]
}
