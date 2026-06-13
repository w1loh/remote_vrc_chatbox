//go:build windows

package main

import (
	"runtime"
	"syscall"
	"unsafe"
)

var (
	modUser32   = syscall.NewLazyDLL("user32.dll")
	modKernel32 = syscall.NewLazyDLL("kernel32.dll")
	modGdi32    = syscall.NewLazyDLL("gdi32.dll")

	procRegisterClassExW = modUser32.NewProc("RegisterClassExW")
	procCreateWindowExW  = modUser32.NewProc("CreateWindowExW")
	procShowWindow       = modUser32.NewProc("ShowWindow")
	procUpdateWindow     = modUser32.NewProc("UpdateWindow")
	procDestroyWindow    = modUser32.NewProc("DestroyWindow")
	procDefWindowProcW   = modUser32.NewProc("DefWindowProcW")
	procGetMessageW      = modUser32.NewProc("GetMessageW")
	procTranslateMessage = modUser32.NewProc("TranslateMessage")
	procDispatchMessageW = modUser32.NewProc("DispatchMessageW")
	procPostQuitMessage  = modUser32.NewProc("PostQuitMessage")
	procSetTimer         = modUser32.NewProc("SetTimer")
	procGetSystemMetrics = modUser32.NewProc("GetSystemMetrics")
	procBeginPaint       = modUser32.NewProc("BeginPaint")
	procEndPaint         = modUser32.NewProc("EndPaint")
	procGetClientRect    = modUser32.NewProc("GetClientRect")
	procFillRect         = modUser32.NewProc("FillRect")
	procDrawTextW        = modUser32.NewProc("DrawTextW")
	procSetTextColor     = modGdi32.NewProc("SetTextColor")
	procSetBkMode        = modGdi32.NewProc("SetBkMode")
	procCreateSolidBrush = modGdi32.NewProc("CreateSolidBrush")
	procCreateFontW      = modGdi32.NewProc("CreateFontW")
	procSelectObject     = modGdi32.NewProc("SelectObject")
	procDeleteObject     = modGdi32.NewProc("DeleteObject")
	procGetModuleHandleW = modKernel32.NewProc("GetModuleHandleW")
)

type wndClassEx struct {
	cbSize        uint32
	style         uint32
	lpfnWndProc   uintptr
	cbClsExtra    int32
	cbWndExtra    int32
	hInstance     uintptr
	hIcon         uintptr
	hCursor       uintptr
	hbrBackground uintptr
	lpszMenuName  *uint16
	lpszClassName *uint16
	hIconSm       uintptr
}

type paintStruct struct {
	hdc         uintptr
	fErase      int32
	rcPaint     winRect
	fRestore    int32
	fIncUpdate  int32
	rgbReserved [32]byte
}

type winRect struct{ left, top, right, bottom int32 }

type winMsg struct {
	hwnd    uintptr
	message uint32
	wParam  uintptr
	lParam  uintptr
	time    uint32
	pt      struct{ x, y int32 }
}

const (
	wsPopup      = 0x80000000
	wsExTopmost  = 0x00000008
	swShow       = 5
	wmDestroy    = 0x0002
	wmPaint      = 0x000F
	wmTimer      = 0x0113
	wmErasebkgnd = 0x0014
	dtCenter     = 0x00000001
	dtVcenter    = 0x00000004
	dtSingleline = 0x00000020
	transparent  = 1
)

func splashWndProc(hwnd, msg, wParam, lParam uintptr) uintptr {
	switch uint32(msg) {
	case wmErasebkgnd:
		return 1

	case wmPaint:
		var ps paintStruct
		hdc, _, _ := procBeginPaint.Call(hwnd, uintptr(unsafe.Pointer(&ps)))

		var rc winRect
		procGetClientRect.Call(hwnd, uintptr(unsafe.Pointer(&rc)))

		bg, _, _ := procCreateSolidBrush.Call(0x17110f)
		procFillRect.Call(hdc, uintptr(unsafe.Pointer(&rc)), bg)
		procDeleteObject.Call(bg)

		accent, _, _ := procCreateSolidBrush.Call(0x8a5a3d)
		bar := winRect{rc.left, rc.bottom - 4, rc.right, rc.bottom}
		procFillRect.Call(hdc, uintptr(unsafe.Pointer(&bar)), accent)
		procDeleteObject.Call(accent)

		procSetBkMode.Call(hdc, transparent)

		titleFont, _, _ := procCreateFontW.Call(
			26, 0, 0, 0, 700, 0, 0, 0,
			128, 0, 0, 0, 0,
			uintptr(unsafe.Pointer(syscall.StringToUTF16Ptr("Meiryo UI"))),
		)
		old, _, _ := procSelectObject.Call(hdc, titleFont)
		procSetTextColor.Call(hdc, 0xf3ede6)
		t, _ := syscall.UTF16PtrFromString("rVRCc Server")
		rc1 := winRect{rc.left, rc.top, rc.right, rc.bottom/2 + 8}
		procDrawTextW.Call(hdc, uintptr(unsafe.Pointer(t)), ^uintptr(0),
			uintptr(unsafe.Pointer(&rc1)), dtCenter|dtVcenter|dtSingleline)
		procDeleteObject.Call(titleFont)

		subFont, _, _ := procCreateFontW.Call(
			13, 0, 0, 0, 400, 0, 0, 0,
			128, 0, 0, 0, 0,
			uintptr(unsafe.Pointer(syscall.StringToUTF16Ptr("Meiryo UI"))),
		)
		procSelectObject.Call(hdc, subFont)
		procSetTextColor.Call(hdc, 0x81766e)
		s, _ := syscall.UTF16PtrFromString("起動しました")
		rc2 := winRect{rc.left, rc.bottom/2 + 8, rc.right, rc.bottom - 4}
		procDrawTextW.Call(hdc, uintptr(unsafe.Pointer(s)), ^uintptr(0),
			uintptr(unsafe.Pointer(&rc2)), dtCenter|dtVcenter|dtSingleline)
		procDeleteObject.Call(subFont)

		procSelectObject.Call(hdc, old)
		procEndPaint.Call(hwnd, uintptr(unsafe.Pointer(&ps)))
		return 0

	case wmTimer:
		procDestroyWindow.Call(hwnd)
		return 0

	case wmDestroy:
		procPostQuitMessage.Call(0)
		return 0
	}
	ret, _, _ := procDefWindowProcW.Call(hwnd, msg, wParam, lParam)
	return ret
}

func showSplash() {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	hInst, _, _ := procGetModuleHandleW.Call(0)
	clsName, _ := syscall.UTF16PtrFromString("rVRCcSplash")

	wce := wndClassEx{
		cbSize:        uint32(unsafe.Sizeof(wndClassEx{})),
		lpfnWndProc:   syscall.NewCallback(splashWndProc),
		hInstance:     hInst,
		lpszClassName: clsName,
	}
	procRegisterClassExW.Call(uintptr(unsafe.Pointer(&wce)))

	sw, _, _ := procGetSystemMetrics.Call(0)
	sh, _, _ := procGetSystemMetrics.Call(1)
	const w, h = 340, 140
	x := (sw - w) / 2
	y := (sh - h) / 2

	titlePtr, _ := syscall.UTF16PtrFromString("rVRCc Server")
	hwnd, _, _ := procCreateWindowExW.Call(
		wsExTopmost,
		uintptr(unsafe.Pointer(clsName)),
		uintptr(unsafe.Pointer(titlePtr)),
		wsPopup,
		x, y, w, h,
		0, 0, hInst, 0,
	)

	procShowWindow.Call(hwnd, swShow)
	procUpdateWindow.Call(hwnd)
	procSetTimer.Call(hwnd, 1, 2000, 0)

	var msg winMsg
	for {
		r, _, _ := procGetMessageW.Call(uintptr(unsafe.Pointer(&msg)), 0, 0, 0)
		if r == 0 {
			break
		}
		procTranslateMessage.Call(uintptr(unsafe.Pointer(&msg)))
		procDispatchMessageW.Call(uintptr(unsafe.Pointer(&msg)))
	}
}
