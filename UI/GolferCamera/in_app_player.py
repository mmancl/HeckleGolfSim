#!/usr/bin/env python3
"""
Embedded In-App YouTube Player Helper for Heckle Golf Sim.
Embeds a borderless Chromium / Edge player window directly into Godot's window HWND
using Win32 SetParent and MoveWindow.
"""

import sys
import os
import time
import shutil
import subprocess
import threading
import ctypes
from ctypes import wintypes

user32 = ctypes.windll.user32
kernel32 = ctypes.windll.kernel32

# Win32 Constants
GWL_STYLE = -16
WS_CHILD = 0x40000000
WS_VISIBLE = 0x10000000
WS_POPUP = 0x80000000
WS_CAPTION = 0x00C00000
WS_THICKFRAME = 0x00040000
WS_CLIPSIBLINGS = 0x04000000
SWP_NOSIZE = 0x0001
SWP_NOMOVE = 0x0002
SWP_NOZORDER = 0x0004
SWP_NOACTIVATE = 0x0010
SWP_FRAMECHANGED = 0x0020
SWP_SHOWWINDOW = 0x0040
SW_SHOW = 5
SW_HIDE = 0


def extract_youtube_id(target: str) -> str:
    """Extract 11-char YouTube ID from any YouTube URL or ID string."""
    target = target.strip()
    if "youtube.com" in target or "youtu.be" in target:
        if "embed/" in target:
            parts = target.split("embed/")[1].split("?")[0].split("&")[0]
            return parts
        elif "v=" in target:
            parts = target.split("v=")[1].split("&")[0].split("#")[0]
            return parts
        elif "youtu.be/" in target:
            parts = target.split("youtu.be/")[1].split("?")[0].split("&")[0]
            return parts
    return target


def find_browser_executable() -> str:
    """Find Microsoft Edge or Google Chrome executable on Windows."""
    candidates = [
        os.path.expandvars(r"%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"),
        os.path.expandvars(r"%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"),
        os.path.expandvars(r"%LocalAppData%\Microsoft\Edge\Application\msedge.exe"),
        os.path.expandvars(r"%ProgramFiles%\Google\Chrome\Application\chrome.exe"),
        os.path.expandvars(r"%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"),
        os.path.expandvars(r"%LocalAppData%\Google\Chrome\Application\chrome.exe"),
    ]
    for path in candidates:
        if os.path.isfile(path):
            return path
    return ""


def get_process_tree_pids(root_pid: int) -> set:
    """Get root_pid and all child/descendant process IDs via Win32 Toolhelp."""
    TH32CS_SNAPPROCESS = 0x00000002

    class PROCESSENTRY32(ctypes.Structure):
        _fields_ = [
            ("dwSize", wintypes.DWORD),
            ("cntUsage", wintypes.DWORD),
            ("th32ProcessID", wintypes.DWORD),
            ("th32DefaultHeapID", ctypes.c_size_t),
            ("th32ModuleID", wintypes.DWORD),
            ("cntThreads", wintypes.DWORD),
            ("th32ParentProcessID", wintypes.DWORD),
            ("pcPriClassBase", ctypes.c_long),
            ("dwFlags", wintypes.DWORD),
            ("szExeFile", ctypes.c_char * 260),
        ]

    hSnap = kernel32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    pe = PROCESSENTRY32()
    pe.dwSize = ctypes.sizeof(PROCESSENTRY32)
    parent_map = {}
    if kernel32.Process32First(hSnap, ctypes.byref(pe)):
        while True:
            parent_map[pe.th32ProcessID] = pe.th32ParentProcessID
            if not kernel32.Process32Next(hSnap, ctypes.byref(pe)):
                break
    kernel32.CloseHandle(hSnap)

    pids = {root_pid}
    changed = True
    while changed:
        changed = False
        for pid, ppid in parent_map.items():
            if ppid in pids and pid not in pids:
                pids.add(pid)
                changed = True
    return pids


def find_window_by_pid_or_descendants(root_pid: int, timeout: float = 6.0) -> int:
    """Find the top-level GUI window belonging to root_pid or any child process."""
    start = time.time()
    WNDENUMPROC = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)

    while time.time() - start < timeout:
        all_pids = get_process_tree_pids(root_pid)
        found_hwnds = []

        def enum_cb(hwnd, _lparam):
            if user32.IsWindowVisible(hwnd):
                curr_pid = wintypes.DWORD()
                user32.GetWindowThreadProcessId(hwnd, ctypes.byref(curr_pid))
                if curr_pid.value in all_pids:
                    rect = wintypes.RECT()
                    user32.GetWindowRect(hwnd, ctypes.byref(rect))
                    width = rect.right - rect.left
                    height = rect.bottom - rect.top
                    if width > 100 and height > 100:
                        found_hwnds.append(hwnd)
            return True

        user32.EnumWindows(WNDENUMPROC(enum_cb), 0)
        if found_hwnds:
            return found_hwnds[0]
        time.sleep(0.12)
    return 0


def main():
    if len(sys.argv) < 7:
        print("Usage: in_app_player.py <parent_hwnd> <x> <y> <w> <h> <video_id_or_url>")
        sys.exit(1)

    parent_hwnd = int(sys.argv[1])
    x = int(sys.argv[2])
    y = int(sys.argv[3])
    w = max(int(sys.argv[4]), 320)
    h = max(int(sys.argv[5]), 180)
    video_target = sys.argv[6]

    video_id = extract_youtube_id(video_target)
    if video_id and len(video_id) == 11:
        target_url = f"https://www.youtube.com/watch?v={video_id}&autoplay=1"
    elif video_target.startswith("http://") or video_target.startswith("https://"):
        target_url = video_target
    else:
        target_url = f"https://www.youtube.com/watch?v={video_target}&autoplay=1"

    browser_exe = find_browser_executable()
    if not browser_exe:
        print("ERROR: No Edge or Chrome executable found on this system.", file=sys.stderr)
        sys.exit(1)

    user_data_dir = os.path.join(
        os.environ.get("TEMP", os.path.expanduser("~")),
        f"heckle_yt_player_{os.getpid()}_{int(time.time())}"
    )
    os.makedirs(user_data_dir, exist_ok=True)

    cmd = [
        browser_exe,
        f"--app={target_url}",
        f"--window-size={w},{h}",
        f"--user-data-dir={user_data_dir}",
        "--no-first-run",
        "--disable-sync",
        "--disable-extensions",
        "--disable-default-apps",
        "--disable-background-mode",
        "--disable-session-crashed-bubble",
        "--autoplay-policy=no-user-gesture-required",
    ]

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )

    # Setup local UDP socket for real-time IPC synchronization with Godot
    import socket
    import tempfile

    udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp_sock.bind(("127.0.0.1", 0))
    udp_port = udp_sock.getsockname()[1]

    port_file = os.path.join(tempfile.gettempdir(), f"heckle_yt_port_{os.getpid()}.txt")
    latest_file = os.path.join(tempfile.gettempdir(), "heckle_yt_ipc_latest.txt")
    ipc_content = f"PORT:{udp_port}\nPYTHON_PID:{os.getpid()}\nBROWSER_PID:{proc.pid}\n"
    try:
        with open(port_file, "w") as pf:
            pf.write(ipc_content)
        with open(latest_file, "w") as lf:
            lf.write(ipc_content)
    except Exception as e:
        print(f"WARN_PORT_FILE:{e}", file=sys.stderr)

    child_hwnd = 0
    tracking_active = True
    cur_visible = True
    last_heartbeat = time.time()
    heartbeat_started = False

    try:
        child_hwnd = find_window_by_pid_or_descendants(proc.pid, timeout=6.0)
        if child_hwnd:
            GWLP_HWNDPARENT = -8

            # Convert style to borderless popup (NOT WS_CHILD, which breaks Chromium GPU composition)
            style = user32.GetWindowLongW(child_hwnd, GWL_STYLE)
            style = (style & ~WS_CAPTION & ~WS_THICKFRAME) | WS_POPUP | WS_VISIBLE | WS_CLIPSIBLINGS
            user32.SetWindowLongW(child_hwnd, GWL_STYLE, style)

            if parent_hwnd > 0:
                # Set Godot as owner window so it stays pinned above Godot and minimizes/restores with Godot
                try:
                    if hasattr(user32, "SetWindowLongPtrW"):
                        user32.SetWindowLongPtrW(child_hwnd, GWLP_HWNDPARENT, parent_hwnd)
                    else:
                        user32.SetWindowLongW(child_hwnd, GWLP_HWNDPARENT, parent_hwnd)
                except Exception:
                    pass

                # Convert Godot client coordinates to absolute desktop screen coordinates
                pt = wintypes.POINT(x, y)
                user32.ClientToScreen(parent_hwnd, ctypes.byref(pt))
                screen_x, screen_y = pt.x, pt.y
            else:
                screen_x, screen_y = x, y

            # Position and reveal borderless window precisely over the placeholder
            user32.SetWindowPos(
                child_hwnd, 0,
                screen_x, screen_y, w, h,
                SWP_NOZORDER | SWP_FRAMECHANGED | SWP_SHOWWINDOW
            )
            user32.ShowWindow(child_hwnd, SW_SHOW)
            user32.UpdateWindow(child_hwnd)
            user32.BringWindowToTop(child_hwnd)
            print(f"READY:{child_hwnd}:PORT:{udp_port}:BPID:{proc.pid}", flush=True)

            # UDP command receiver for instant sub-millisecond updates from Godot (scroll, resize, move)
            def udp_listener():
                nonlocal tracking_active, x, y, w, h, cur_visible, last_heartbeat, heartbeat_started
                while tracking_active:
                    try:
                        data, _ = udp_sock.recvfrom(256)
                        if not data:
                            continue
                        last_heartbeat = time.time()
                        heartbeat_started = True

                        msg = data.decode("utf-8").strip()
                        if msg in ("QUIT", "CLOSE", "EXIT"):
                            tracking_active = False
                            break
                        elif msg.startswith("POS "):
                            parts = msg.split()
                            if len(parts) >= 6:
                                nx, ny, nw, nh, nvis = int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5])
                                x, y, w, h = nx, ny, nw, nh
                                cur_visible = (nvis != 0)
                                if not cur_visible:
                                    user32.ShowWindow(child_hwnd, SW_HIDE)
                                else:
                                    pt_cmd = wintypes.POINT(x, y)
                                    if parent_hwnd > 0:
                                        user32.ClientToScreen(parent_hwnd, ctypes.byref(pt_cmd))
                                    user32.SetWindowPos(
                                        child_hwnd, 0,
                                        pt_cmd.x, pt_cmd.y, w, h,
                                        SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW
                                    )
                                    user32.ShowWindow(child_hwnd, SW_SHOW)
                    except Exception:
                        if not tracking_active:
                            break

            udp_thread = threading.Thread(target=udp_listener, daemon=True)
            udp_thread.start()

            # Background thread to keep docked window synchronized and watch for modal close / loss of heartbeat
            def sync_tracker():
                nonlocal tracking_active
                last_pt = (screen_x, screen_y)
                was_iconic = False
                while tracking_active:
                    time.sleep(0.03)
                    if parent_hwnd <= 0 or not child_hwnd:
                        continue
                    if not user32.IsWindow(parent_hwnd):
                        tracking_active = False
                        break

                    # Fail-safe watchdog: If modal closed, Godot stops sending POS packets. Auto-exit after 0.8s silence.
                    if heartbeat_started and (time.time() - last_heartbeat > 0.8):
                        print("[InAppPlayer] Heartbeat timeout (modal closed). Exiting.", flush=True)
                        tracking_active = False
                        break

                    # Handle minimize/restore of Godot
                    is_iconic = bool(user32.IsIconic(parent_hwnd))
                    if is_iconic and not was_iconic:
                        user32.ShowWindow(child_hwnd, SW_HIDE)
                        was_iconic = True
                    elif not is_iconic and was_iconic:
                        if cur_visible:
                            user32.ShowWindow(child_hwnd, SW_SHOW)
                        was_iconic = False

                    if not is_iconic and cur_visible:
                        curr_pt = wintypes.POINT(x, y)
                        user32.ClientToScreen(parent_hwnd, ctypes.byref(curr_pt))
                        if (curr_pt.x, curr_pt.y) != last_pt:
                            last_pt = (curr_pt.x, curr_pt.y)
                            user32.SetWindowPos(
                                child_hwnd, 0,
                                curr_pt.x, curr_pt.y, w, h,
                                SWP_NOZORDER | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW
                            )

            tracker_thread = threading.Thread(target=sync_tracker, daemon=True)
            tracker_thread.start()

            # Keep main thread alive until tracking stops or process receives kill
            while tracking_active:
                time.sleep(0.05)
                if parent_hwnd > 0 and not user32.IsWindow(parent_hwnd):
                    break
        else:
            print(f"FAILED_FIND_WINDOW:pid={proc.pid}", flush=True)

    finally:
        tracking_active = False
        try:
            udp_sock.close()
        except Exception:
            pass
        try:
            if os.path.exists(port_file):
                os.remove(port_file)
        except Exception:
            pass
        try:
            if os.path.exists(latest_file):
                os.remove(latest_file)
        except Exception:
            pass

        # Clean teardown of browser process tree
        try:
            if proc and proc.pid:
                subprocess.run(
                    ["taskkill", "/F", "/T", "/PID", str(proc.pid)],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )
        except Exception:
            pass
        try:
            proc.terminate()
            proc.wait(timeout=0.5)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass

        # Cleanup temp user data directory
        try:
            if os.path.exists(user_data_dir):
                shutil.rmtree(user_data_dir, ignore_errors=True)
        except Exception:
            pass


if __name__ == "__main__":
    main()
