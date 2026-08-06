#ifndef FLAGS2ENV_BROWSER_COMPAT_H
#define FLAGS2ENV_BROWSER_COMPAT_H

/*
 * The browser build is deliberately single-threaded and does not export any
 * stdio-printing APIs. Emscripten's libc does not declare the POSIX
 * flockfile/funlockfile pair used by native help-print helpers, so compile
 * those locks as evaluated no-ops only for this WebAssembly target.
 */
#if defined(__EMSCRIPTEN__) && !defined(__EMSCRIPTEN_PTHREADS__)
#define flockfile(stream) ((void)(stream))
#define funlockfile(stream) ((void)(stream))
#endif

#endif
