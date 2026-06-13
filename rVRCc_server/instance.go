//go:build windows

package main

import (
	"os"
	"syscall"
	"unsafe"
)

var keepMutex syscall.Handle

func acquireSingleInstance() {
	procCreateMutexW := modKernel32.NewProc("CreateMutexW")
	procMessageBoxW := modUser32.NewProc("MessageBoxW")

	name, _ := syscall.UTF16PtrFromString("Local\\rVRCcServer")
	h, _, err := procCreateMutexW.Call(0, 0, uintptr(unsafe.Pointer(name)))

	const errAlreadyExists = syscall.Errno(0xb7)
	if err == errAlreadyExists {
		msg, _ := syscall.UTF16PtrFromString("rVRCc Server はすでに起動しています。\nタスクトレイのアイコンを確認してください。")
		ttl, _ := syscall.UTF16PtrFromString("rVRCc Server")
		procMessageBoxW.Call(0,
			uintptr(unsafe.Pointer(msg)),
			uintptr(unsafe.Pointer(ttl)),
			0x30,
		)
		os.Exit(0)
	}

	keepMutex = syscall.Handle(h)
}
