#ifndef RUNNER_NATIVE_LOG_H_
#define RUNNER_NATIVE_LOG_H_

#include <windows.h>

// Sends stderr, for the runner and the Flutter engine alike, to native.log in
// the app support folder (next to startup.log), unless a console is attached.
// The engine reports rendering problems there, which a release build would
// otherwise drop.
void OpenNativeLog();

// Writes one timed line ("+12ms text") to native.log.
void NativeLog(const char* format, ...);

// Writes a window's rectangle, visibility and DWM cloaking, as "label: ...".
void NativeLogWindow(const char* label, HWND window);

// Logs every other StackSpace window and process that exists now (another
// instance, or a previous run still shutting down).
void NativeLogOtherInstances(HWND self);

#endif  // RUNNER_NATIVE_LOG_H_
