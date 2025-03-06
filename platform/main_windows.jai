#import "Basic";
#import "Winblows";

#load "renderer.jai";

ascii_to_utf16lez :: (s: string) -> []u16 {
	utf16le: [..]u16;
	array_reserve(*utf16le, s.count + 1);
	for s array_add(*utf16le, it);
	array_add(*utf16le, 0);
	return utf16le;
}

platform_hinstance: HINSTANCE;
platform_hwnd: HWND;
platform_hdc: HDC;
platform_width: u16;
platform_height: u16;
platform_save_placement := WINDOWPLACEMENT.{length = size_of(WINDOWPLACEMENT)};
platform_renderer: *Platform_Renderer;

main :: () {
	update_cursor_clip :: () {
		ClipCursor(null);
	}

	clear_held_keys :: () {

	}

	toggle_fullscreen :: () {
		style := cast(u32) GetWindowLongW(platform_hwnd, GWL_STYLE);
		if style & WS_OVERLAPPEDWINDOW {
			mi := MONITORINFO.{cbSize = size_of(MONITORINFO)};
			GetMonitorInfoW(MonitorFromWindow(platform_hwnd, MONITOR_DEFAULTTONEAREST), *mi);

			GetWindowPlacement(platform_hwnd, *platform_save_placement);
			SetWindowLongW(platform_hwnd, GWL_STYLE, xx (style & ~cast(u32) WS_OVERLAPPEDWINDOW));
			SetWindowPos(platform_hwnd, HWND_TOP, mi.rcMonitor.left, mi.rcMonitor.top,
				mi.rcMonitor.right - mi.rcMonitor.left, mi.rcMonitor.bottom - mi.rcMonitor.top,
				SWP_FRAMECHANGED);
		} else {
			SetWindowLongW(platform_hwnd, GWL_STYLE, xx (style | WS_OVERLAPPEDWINDOW));
			SetWindowPlacement(platform_hwnd, *platform_save_placement);
			SetWindowPos(platform_hwnd, null, 0, 0, 0, 0, SWP_NOMOVE |
				SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
		}
	}

	platform_hinstance = GetModuleHandleW(null);

	wsadata: WSADATA = ---;
	networking_supported := WSAStartup(0x202, *wsadata) == 0;
	defer if networking_supported WSACleanup();

	sleep_is_granular := timeBeginPeriod(1) == TIMERR_NOERROR;

	clock_frequency: s64;
	QueryPerformanceFrequency(*clock_frequency);
	clock_start: s64;
	QueryPerformanceCounter(*clock_start);
	clock_previous := clock_start;

	SetProcessDPIAware();
	wndclass: WNDCLASSEXW;
	wndclass.cbSize = size_of(WNDCLASSEXW);
	wndclass.style = CS_OWNDC;
	wndclass.lpfnWndProc = xx (hwnd: HWND, message: u32, wParam: u64, lParam: s64) -> s64 #c_call {
		push_context,defer_pop .{};
		if message == {
			case WM_PAINT;
				ValidateRect(hwnd, null);
			case WM_ERASEBKGND;
				return 1;
			case WM_ACTIVATEAPP;
				tabbing_in := wParam != 0;

				if tabbing_in update_cursor_clip();
				else clear_held_keys();
			case WM_SIZE;
				platform_width = cast,no_check(u16) lParam;
				platform_height = cast,no_check(u16) (lParam >> 16);

				platform_renderer.resize();
			case WM_CREATE;
				platform_hwnd = hwnd;
				platform_hdc = GetDC(hwnd);

				dark_mode: s32 = xx true;
				DwmSetWindowAttribute(platform_hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, *dark_mode, size_of(type_of(dark_mode)));
				round_mode: s32 = DWMWCP_DONOTROUND;
				DwmSetWindowAttribute(platform_hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, *round_mode, size_of(type_of(round_mode)));

				renderer_switch_api(.D3D11);
			case WM_DESTROY;
				platform_renderer.deinit();

				PostQuitMessage(0);
			case WM_SYSCOMMAND;
				if wParam == SC_KEYMENU return 0;
				#through;
			case;
				return DefWindowProcW(hwnd, message, wParam, lParam);
		}
		return 0;
	};
	wndclass.hInstance = platform_hinstance;
	wndclass.hIcon = LoadIconW(null, IDI_WARNING);
	wndclass.hCursor = LoadCursorW(null, IDC_CROSS);
	wndclass.lpszClassName = (#run ascii_to_utf16lez("A")).data;
	RegisterClassExW(*wndclass);
	CreateWindowExW(0, wndclass.lpszClassName, (#run ascii_to_utf16lez("Red Wheelbarrow")).data,
		WS_OVERLAPPEDWINDOW | WS_VISIBLE,
		CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT,
		null, null, platform_hinstance, null);

	while main_loop := true {
		clock_frame_start: s64;
		QueryPerformanceCounter(*clock_frame_start);

		msg: MSG = ---;
		while PeekMessageW(*msg, null, 0, 0, PM_REMOVE) {
			using msg;
			TranslateMessage(*msg);
			if message == {
				case WM_KEYDOWN; #through;
				case WM_KEYUP; #through;
				case WM_SYSKEYDOWN; #through;
				case WM_SYSKEYUP;
					pressed := msg.lParam & (1 << 31) == 0;
					repeat := pressed && msg.lParam & (1 << 30) != 0;
					sys := msg.message == WM_SYSKEYDOWN || msg.message == WM_SYSKEYUP;
					alt := sys && msg.lParam & (1 << 29) != 0;

					if !repeat && (!sys || alt || msg.wParam == VK_MENU || msg.wParam == VK_F10) {
						if pressed {
							if msg.wParam == VK_F4 && alt DestroyWindow(platform_hwnd);
							if DEBUG && msg.wParam == VK_ESCAPE DestroyWindow(platform_hwnd);
							if msg.wParam == VK_RETURN && alt toggle_fullscreen();
							if msg.wParam == VK_F11 toggle_fullscreen();
						}
					}
				case WM_QUIT;
					break main_loop;
				case;
					DispatchMessageW(*msg);
			}
		}

		clock_current: s64;
		QueryPerformanceCounter(*clock_current);
		delta := cast(float32) (clock_current - clock_previous) / cast(float32) clock_frequency;
		defer clock_previous = clock_current;

		// game_renderer: Game_Renderer;
		// game_renderer.procs = renderer.procs;
		// game_update_and_render(*game_renderer);

		platform_renderer.present();

		clock_frame_end: s64;
		QueryPerformanceCounter(*clock_frame_end);

		if sleep_is_granular {
			ideal_ms := 7;
			frame_ms := (clock_frame_end - clock_frame_end) / (clock_frequency / 1000);
			if ideal_ms > frame_ms {
				Sleep(xx (ideal_ms - frame_ms));
			}
		}
	}
}
