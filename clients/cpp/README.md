# flags2env C++

Header-only C++ helpers over the `flags2env` C ABI.

```cpp
#include "flags2env.hpp"

auto env = flags2env::parse({"app", "--port", "8080"});
```

Builds should link the native `flags2env` library or compile `src/parser.c`
alongside the C++ target.
