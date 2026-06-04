# flags2env C++

Header-only C++ helpers over the `flags2env` C ABI.

```cpp
#include "flags2env.hpp"

auto env = flags2env::parse({"app", "--port", "8080"});
```

The CMake target builds the bundled C parser sources from `native/` and exposes
the header-only C++ helpers from `include/`.
