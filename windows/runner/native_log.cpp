#include "native_log.h"

#include <dwmapi.h>
#include <flutter_windows.h>
#include <io.h>
#include <shlobj.h>
#include <tlhelp32.h>

#include <cstdarg>
#include <cstdio>
#include <string>

namespace {

ULONGLONG g_start = GetTickCount64();

// native.log is started afresh once it grows past this.
constexpr DWORD kMaxLogBytes = 256 * 1024;

std::wstring LogPath() {
  PWSTR roaming = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr,
                                  &roaming))) {
    return L"";
  }
  std::wstring folder = std::wstring(roaming) + L"\\com.stackspace";
  CoTaskMemFree(roaming);
  CreateDirectory(folder.c_str(), nullptr);
  folder += L"\\stack_space";
  CreateDirectory(folder.c_str(), nullptr);
  return folder + L"\\native.log";
}

}  // namespace

void OpenNativeLog() {
  std::wstring path = LogPath();
  if (path.empty()) {
    return;
  }
  const wchar_t* mode = L"a";
  WIN32_FILE_ATTRIBUTE_DATA data;
  if (GetFileAttributesEx(path.c_str(), GetFileExInfoStandard, &data) &&
      (data.nFileSizeHigh != 0 || data.nFileSizeLow > kMaxLogBytes)) {
    mode = L"w";
  }
  FILE* unused;
  if (_wfreopen_s(&unused, path.c_str(), mode, stderr) != 0) {
    return;
  }
  setvbuf(stderr, nullptr, _IONBF, 0);
  // Point file descriptor 2 at the file too, for code that writes to it
  // directly. Not FlutterDesktopResyncOutputStreams: it reopens stderr on a
  // console, and without one it ends the process.
  if (_fileno(stderr) >= 0 && _fileno(stderr) != 2) {
    _dup2(_fileno(stderr), 2);
  }

  SYSTEMTIME now;
  GetLocalTime(&now);
  fprintf(stderr,
          "---- launch %04d-%02d-%02dT%02d:%02d:%02d.%03d pid %lu ----\n",
          now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute,
          now.wSecond, now.wMilliseconds, GetCurrentProcessId());
  // Which build is running, and from where, so a launch of an older copy
  // (an old shortcut or taskbar pin) can be told apart from the current one.
#ifdef FLUTTER_VERSION
  const char* version = FLUTTER_VERSION;
#else
  const char* version = "unknown";
#endif
  wchar_t exe[MAX_PATH] = L"";
  GetModuleFileName(nullptr, exe, MAX_PATH);
  fprintf(stderr, "version %s, exe %ls\n", version, exe);
}

void NativeLog(const char* format, ...) {
  fprintf(stderr, "+%llums ", GetTickCount64() - g_start);
  va_list args;
  va_start(args, format);
  vfprintf(stderr, format, args);
  va_end(args);
  fputc('\n', stderr);
  fflush(stderr);
}

void NativeLogWindow(const char* label, HWND window) {
  if (window == nullptr || !IsWindow(window)) {
    NativeLog("%s: no window", label);
    return;
  }
  RECT rect;
  GetWindowRect(window, &rect);
  RECT client;
  GetClientRect(window, &client);
  BOOL cloaked = 0;
  DwmGetWindowAttribute(window, DWMWA_CLOAKED, &cloaked, sizeof(cloaked));
  NativeLog(
      "%s: rect %ld,%ld %ldx%ld, client %ldx%ld, visible %d, minimized %d, "
      "maximized %d, cloaked %d, dpi %u",
      label, rect.left, rect.top, rect.right - rect.left,
      rect.bottom - rect.top, client.right, client.bottom,
      IsWindowVisible(window) ? 1 : 0, IsIconic(window) ? 1 : 0,
      IsZoomed(window) ? 1 : 0, cloaked,
      FlutterDesktopGetDpiForMonitor(
          MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST)));
}

void NativeLogOtherInstances(HWND self) {
  struct Search {
    HWND self;
    int found;
  } search = {self, 0};
  EnumWindows(
      [](HWND window, LPARAM param) -> BOOL {
        auto* search = reinterpret_cast<Search*>(param);
        wchar_t name[64];
        if (window == search->self ||
            GetClassName(window, name, 64) == 0 ||
            wcscmp(name, L"FLUTTER_RUNNER_WIN32_WINDOW") != 0) {
          return TRUE;
        }
        DWORD pid = 0;
        GetWindowThreadProcessId(window, &pid);
        char label[64];
        snprintf(label, sizeof(label), "other instance, pid %lu", pid);
        NativeLogWindow(label, window);
        search->found++;
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&search));
  if (search.found == 0) {
    NativeLog("no other StackSpace window");
  }

  // A previous run can still be shutting down after its window has gone.
  wchar_t own_path[MAX_PATH];
  GetModuleFileName(nullptr, own_path, MAX_PATH);
  const wchar_t* own_name = wcsrchr(own_path, L'\\');
  own_name = own_name ? own_name + 1 : own_path;
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) {
    return;
  }
  PROCESSENTRY32 entry = {sizeof(PROCESSENTRY32)};
  int processes = 0;
  for (BOOL more = Process32First(snapshot, &entry); more;
       more = Process32Next(snapshot, &entry)) {
    if (entry.th32ProcessID != GetCurrentProcessId() &&
        _wcsicmp(entry.szExeFile, own_name) == 0) {
      NativeLog("other process still running: pid %lu", entry.th32ProcessID);
      processes++;
    }
  }
  CloseHandle(snapshot);
  if (processes == 0) {
    NativeLog("no other process");
  }
}
