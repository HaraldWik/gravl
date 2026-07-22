const Win32 = @This();

// zig build -Dtarget=x86_64-windows && wine zig-out/bin/real_engine.exe

const std = @import("std");
const win32 = @import("win32").everything;

const Window = @import("../Window.zig");

gpa: std.mem.Allocator,
hinstance: std.os.windows.HINSTANCE,
class: win32.WNDCLASSEXW,
hwnd: std.os.windows.HWND,

pub fn open(self: *Win32, window: *Window, options: Window.OpenOptions, gpa: std.mem.Allocator) anyerror!void {
    _ = window;
    const hinstance: std.os.windows.HINSTANCE = @ptrCast(win32.GetModuleHandleW(null) orelse return error.GetInstanceHandle);

    const class = std.mem.zeroInit(win32.WNDCLASSEXW, .{
        .cbSize = @sizeOf(win32.WNDCLASSEXW),
        .lpszClassName = std.unicode.utf8ToUtf16LeStringLiteral(if (options.app_id) |id| @tagName(id) else "Class"),
        .lpfnWndProc = wndProc,
        .hInstance = hinstance,
        .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
    });
    errdefer _ = win32.UnregisterClassW(class.lpszClassName, @ptrCast(hinstance));
    check(win32.RegisterClassExW(@ptrCast(&class))) catch return error.RegisterClass;
    const title = try std.unicode.utf8ToUtf16LeAllocZ(gpa, options.title);
    defer gpa.free(title);

    const hwnd = win32.CreateWindowExW(
        .{ .TRANSPARENT = 1 },
        class.lpszClassName,
        @ptrCast(title),
        win32.WS_OVERLAPPEDWINDOW,
        if (options.position) |position| position.x else @max(0, @divTrunc(win32.GetSystemMetrics(.CXSCREEN) - @as(i32, @intCast(options.size.width)), 2)),
        if (options.position) |position| position.y else @max(0, @divTrunc(win32.GetSystemMetrics(.CYSCREEN) - @as(i32, @intCast(options.size.height)), 2)),
        @intCast(options.size.width),
        @intCast(options.size.height),
        null,
        null,
        hinstance,
        null,
    ) orelse {
        reportErr();
        return error.CreateWindowFailed;
    };
    errdefer _ = win32.DestroyWindow(hwnd);

    _ = win32.ShowWindow(hwnd, .{ .SHOWNORMAL = 1 });
    check(win32.UpdateWindow(hwnd)) catch return error.UpdateWindow;

    self.* = .{
        .gpa = gpa,
        .hinstance = hinstance,
        .class = class,
        .hwnd = @ptrCast(hwnd),
    };
}

pub fn close(self: *Win32, window: *Window) void {
    _ = window;
    _ = win32.DestroyWindow(@ptrCast(self.hwnd));
    _ = win32.UnregisterClassW(self.class.lpszClassName, @ptrCast(self.hinstance));
}

pub fn poll(self: *Win32, window: *Window) !void {
    while (true) {
        var msg: win32.MSG = undefined;
        if (win32.PeekMessageW(&msg, @ptrCast(self.hwnd), 0, 0, .{ .REMOVE = 1 }) == 0) break;
        _ = win32.TranslateMessage(&msg);
        check(win32.DispatchMessageW(&msg)) catch return error.DispatchMessage;

        std.log.info("msg: {d}", .{msg.message});

        switch (msg.message) {
            win32.WM_USER + win32.WM_CLOSE => window.should_close = true,
            win32.WM_USER + win32.WM_SIZE => window.size = .{
                .width = @intCast(@as(u16, @truncate(std.math.cast(u32, msg.lParam) orelse continue))),
                .height = @intCast(@as(u16, @truncate(std.math.cast(u32, msg.lParam >> 16) orelse continue))),
            },
            win32.WM_USER + win32.WM_MOVE => window.position = .{
                .x = @intCast(@as(u16, @truncate(std.math.cast(u32, msg.lParam) orelse continue))),
                .y = @intCast(@as(u16, @truncate(std.math.cast(u32, msg.lParam >> 16) orelse continue))),
            },
            win32.WM_USER + win32.WM_SETFOCUS => {
                // capture mouse
                window.focused = true;
            },
            win32.WM_USER + win32.WM_KILLFOCUS => window.focused = false,
            else => return,
        }
    }
}

fn wndProc(hwnd: win32.HWND, msg: u32, wParam: usize, lParam: isize) callconv(.winapi) isize {
    return switch (msg) {
        win32.WM_GETMINMAXINFO, win32.WM_SIZE, win32.WM_MOVE, win32.WM_SETFOCUS, win32.WM_KILLFOCUS, win32.WM_CLOSE => |wm| {
            check(win32.PostMessageW(hwnd, win32.WM_USER + wm, wParam, lParam)) catch {};
            return 0;
        },
        else => win32.DefWindowProcW(hwnd, msg, wParam, lParam),
    };
}

pub fn check(result: anytype) error{Error}!void {
    if (result >= 0) return;
    reportErr();
    return error.Error;
}

pub fn reportErr() void {
    @branchHint(.unlikely);

    const code = win32.GetLastError();

    var text_buffer: [512:0]u16 = undefined;
    const text_len = win32.FormatMessageW(
        .{ .FROM_SYSTEM = 1, .IGNORE_INSERTS = 1 },
        null,
        @intFromEnum(code),
        0,
        @ptrCast(&text_buffer),
        text_buffer.len,
        null,
    );
    const title = std.unicode.utf8ToUtf16LeStringLiteral("Error\x00");

    _ = win32.MessageBoxW(
        null,
        @ptrCast(text_buffer[0..text_len]),
        @ptrCast(title),
        .{ .ICONHAND = 1 },
    );
}
