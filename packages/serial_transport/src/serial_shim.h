/*
    Minimal cross-platform serial port access for serial_transport.

    Only raw byte I/O and port enumeration live here: protocols are handled in
    Dart, so the same code runs on the web and on Android.

    Copyright (c) 2025 zeyus. MIT License (see LICENSE).

    Port setup follows stream_serial.cpp of hyperscanner_lib (Aarhus
    University).

    Functions that can fail take an `err` buffer, which receives a
    NUL-terminated message on failure. There is no global or thread-local
    state, since Dart isolates are not pinned to OS threads.
*/
#ifndef SERIAL_SHIM_H
#define SERIAL_SHIM_H

#include <stdint.h>

#if defined(_WIN32)
#define HSS_EXPORT __declspec(dllexport)
#else
#define HSS_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// Invalid port handle, returned by hss_open() on failure.
#define HSS_INVALID_HANDLE ((intptr_t)-1)

/// List the USB serial ports present on the system.
///
/// Writes one line per port to `buf` (NUL-terminated, truncated to `buf_len`):
///   <path>\t<description>\t<vendor id hex>\t<product id hex>\t<USB product>\n
/// Vendor and product ids, and the USB product string (the bus reported
/// device description on Windows), are empty when unknown.
///
/// Returns the buffer size needed for the full list (including the NUL), so a
/// caller can retry with a larger buffer, or -1 on error.
HSS_EXPORT int hss_list_ports(char *buf, int buf_len);

/// Open a serial port (e.g. "/dev/ttyACM0", "/dev/cu.usbmodem1", "COM3") in
/// raw 8N1 mode with exclusive access and DTR disabled, and flush its buffers.
///
/// Returns a handle, or HSS_INVALID_HANDLE on failure.
HSS_EXPORT intptr_t hss_open(const char *path, char *err, int err_len);

/// Like hss_open(), at `baud` bits per second (0 for the default, 230400;
/// USB CDC devices ignore it). On POSIX systems the standard rates are
/// supported, and on macOS any rate.
HSS_EXPORT intptr_t hss_open_baud(const char *path, int baud, char *err,
                                  int err_len);

/// Read up to `len` bytes, waiting at most `timeout_ms` for the first byte.
///
/// Returns the number of bytes read, 0 on timeout, or -1 on error or when the
/// device was disconnected.
HSS_EXPORT int hss_read(intptr_t handle, uint8_t *buf, int len, int timeout_ms,
                        char *err, int err_len);

/// Write all `len` bytes. Returns `len` on success or -1 on error.
HSS_EXPORT int hss_write(intptr_t handle, const uint8_t *buf, int len,
                         char *err, int err_len);

/// Close a handle returned by hss_open(). Returns 0 on success, -1 otherwise.
HSS_EXPORT int hss_close(intptr_t handle);

#ifdef __cplusplus
}
#endif

#endif /* SERIAL_SHIM_H */
