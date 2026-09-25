/*
    Minimal cross-platform serial port access for serial_transport.
    See serial_shim.h.

    Copyright (c) 2025 zeyus. MIT License (see LICENSE).

    Port configuration follows stream_serial.cpp of hyperscanner_lib
    (Aarhus University).
*/

#if !defined(_WIN32)
#define _DEFAULT_SOURCE /* cfmakeraw, realpath, strncasecmp on glibc */
#endif

#include "serial_shim.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

/* ------------------------------------------------------------------------ */
/* Shared helpers                                                           */
/* ------------------------------------------------------------------------ */

static void set_err(char *err, int err_len, const char *fmt, ...)
{
    if (err == NULL || err_len <= 0)
        return;
    va_list args;
    va_start(args, fmt);
    vsnprintf(err, (size_t)err_len, fmt, args);
    va_end(args);
}

/* Appends to a caller buffer, tracking the size needed for everything. */
typedef struct
{
    char *buf;
    int cap;
    int needed; /* excluding the terminating NUL */
} out_buf_t;

static void out_append(out_buf_t *out, const char *s)
{
    size_t n = strlen(s);
    if (out->buf != NULL && out->cap > 0)
    {
        int room = out->cap - 1 - out->needed;
        if (room > 0)
        {
            size_t copy = n < (size_t)room ? n : (size_t)room;
            memcpy(out->buf + out->needed, s, copy);
            out->buf[out->needed + (int)copy] = '\0';
        }
    }
    out->needed += (int)n;
}

/* Tabs and newlines separate fields and records, so keep them out of values. */
static void sanitize(char *s)
{
    for (; *s; ++s)
        if (*s == '\t' || *s == '\n' || *s == '\r')
            *s = ' ';
}

static void out_port(out_buf_t *out, const char *path, char *desc,
                     const char *vid, const char *pid, char *product)
{
    sanitize(desc);
    sanitize(product);
    out_append(out, path);
    out_append(out, "\t");
    out_append(out, desc);
    out_append(out, "\t");
    out_append(out, vid);
    out_append(out, "\t");
    out_append(out, pid);
    out_append(out, "\t");
    out_append(out, product);
    out_append(out, "\n");
}

#if defined(_WIN32)
/* ======================================================================== */
/* Windows                                                                  */
/* ======================================================================== */

#include <windows.h>
#include <setupapi.h>
#include <devpropdef.h>
#include <devguid.h>

/* DEVPKEY_Device_BusReportedDeviceDesc, defined here as in stream_serial.cpp */
static const DEVPROPKEY hss_DEVPKEY_Device_BusReportedDeviceDesc = {
    {0x540b947e, 0x8b40, 0x45bc, {0xa8, 0xa2, 0x6a, 0x0b, 0x89, 0x4c, 0xbd, 0xa2}}, 4};

static void win_err(char *err, int err_len, const char *what)
{
    DWORD code = GetLastError();
    char msg[256] = "";
    FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL, code,
                   0, msg, sizeof(msg), NULL);
    size_t n = strlen(msg);
    while (n > 0 && (msg[n - 1] == '\n' || msg[n - 1] == '\r' || msg[n - 1] == ' '))
        msg[--n] = '\0';
    set_err(err, err_len, "%s (error %lu: %s)", what, (unsigned long)code, msg);
}

static void wide_to_utf8(const WCHAR *in, char *out, int out_len)
{
    if (WideCharToMultiByte(CP_UTF8, 0, in, -1, out, out_len, NULL, NULL) == 0)
        out[0] = '\0';
}

/* Find "VID_xxxx" / "PID_xxxx" in a hardware id and copy the 4 hex digits. */
static void hwid_field(const WCHAR *hwid, const WCHAR *key, char *out)
{
    const WCHAR *p = wcsstr(hwid, key);
    out[0] = '\0';
    if (p == NULL)
        return;
    p += wcslen(key);
    int i = 0;
    for (; i < 4 && p[i]; ++i)
        out[i] = (char)p[i];
    out[i] = '\0';
}

int hss_list_ports(char *buf, int buf_len)
{
    out_buf_t out = {buf, buf_len, 0};
    if (buf != NULL && buf_len > 0)
        buf[0] = '\0';

    HDEVINFO info = SetupDiGetClassDevsW(&GUID_DEVCLASS_PORTS, NULL, NULL, DIGCF_PRESENT);
    if (info == INVALID_HANDLE_VALUE)
        return -1;

    SP_DEVINFO_DATA dev = {0};
    dev.cbSize = sizeof(dev);
    for (DWORD i = 0; SetupDiEnumDeviceInfo(info, i, &dev); ++i)
    {
        /* COM port name from the device registry key */
        char port_name[64] = "";
        HKEY key = SetupDiOpenDevRegKey(info, &dev, DICS_FLAG_GLOBAL, 0, DIREG_DEV, KEY_READ);
        if (key == INVALID_HANDLE_VALUE)
            continue;
        DWORD size = sizeof(port_name) - 1;
        DWORD type = 0;
        LONG rc = RegQueryValueExA(key, "PortName", NULL, &type, (LPBYTE)port_name, &size);
        RegCloseKey(key);
        if (rc != ERROR_SUCCESS || type != REG_SZ || strncmp(port_name, "COM", 3) != 0)
            continue;
        port_name[sizeof(port_name) - 1] = '\0';

        /* Only USB devices */
        WCHAR hwid[1024] = L"";
        if (!SetupDiGetDeviceRegistryPropertyW(info, &dev, SPDRP_HARDWAREID, NULL, (PBYTE)hwid,
                                               sizeof(hwid) - sizeof(WCHAR), NULL))
            continue;
        if (wcsncmp(hwid, L"USB\\", 4) != 0 && wcsstr(hwid, L"VID_") == NULL)
            continue;
        char vid[8], pid[8];
        hwid_field(hwid, L"VID_", vid);
        hwid_field(hwid, L"PID_", pid);

        char desc[512] = "";
        WCHAR wdesc[256];
        if (SetupDiGetDeviceRegistryPropertyW(info, &dev, SPDRP_FRIENDLYNAME, NULL, (PBYTE)wdesc,
                                              sizeof(wdesc), NULL))
            wide_to_utf8(wdesc, desc, sizeof(desc));

        char product[512] = "";
        DEVPROPTYPE prop_type;
        WCHAR bus_desc[256];
        if (SetupDiGetDevicePropertyW(info, &dev, &hss_DEVPKEY_Device_BusReportedDeviceDesc,
                                      &prop_type, (PBYTE)bus_desc, sizeof(bus_desc), NULL, 0) &&
            prop_type == DEVPROP_TYPE_STRING)
        {
            wide_to_utf8(bus_desc, product, sizeof(product));
        }

        out_port(&out, port_name, desc, vid, pid, product);
    }
    SetupDiDestroyDeviceInfoList(info);
    return out.needed + 1;
}

intptr_t hss_open(const char *path, char *err, int err_len)
{
    return hss_open_baud(path, 0, err, err_len);
}

intptr_t hss_open_baud(const char *path, int baud, char *err, int err_len)
{
    char full[300];
    /* Required for COM10 and up */
    snprintf(full, sizeof(full), "\\\\.\\%s", path);
    HANDLE h = CreateFileA(full, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
    if (h == INVALID_HANDLE_VALUE)
    {
        win_err(err, err_len, "Failed to open serial port");
        return HSS_INVALID_HANDLE;
    }

    DCB dcb = {0};
    dcb.DCBlength = sizeof(dcb);
    if (!GetCommState(h, &dcb))
    {
        win_err(err, err_len, "Failed to get serial parameters");
        CloseHandle(h);
        return HSS_INVALID_HANDLE;
    }
    /* USB CDC ignores the baud rate; 230400 unless asked otherwise */
    dcb.BaudRate = baud > 0 ? (DWORD)baud : 230400;
    dcb.ByteSize = 8;
    dcb.StopBits = ONESTOPBIT;
    dcb.Parity = NOPARITY;
    dcb.fBinary = TRUE;
    dcb.fDtrControl = DTR_CONTROL_DISABLE;
    dcb.fRtsControl = RTS_CONTROL_DISABLE;
    dcb.fOutxCtsFlow = FALSE;
    dcb.fOutxDsrFlow = FALSE;
    dcb.fOutX = FALSE;
    dcb.fInX = FALSE;
    if (!SetCommState(h, &dcb))
    {
        win_err(err, err_len, "Failed to set serial parameters");
        CloseHandle(h);
        return HSS_INVALID_HANDLE;
    }

    /* hss_read() sets the read timeouts per call; this bounds writes before the first read */
    COMMTIMEOUTS t = {0};
    t.ReadIntervalTimeout = MAXDWORD;
    t.WriteTotalTimeoutConstant = 2000;
    SetCommTimeouts(h, &t);

    PurgeComm(h, PURGE_RXABORT | PURGE_RXCLEAR | PURGE_TXABORT | PURGE_TXCLEAR);
    return (intptr_t)h;
}

int hss_read(intptr_t handle, uint8_t *buf, int len, int timeout_ms, char *err, int err_len)
{
    HANDLE h = (HANDLE)handle;
    /* Return as soon as any bytes are available, waiting up to timeout_ms for the first one */
    COMMTIMEOUTS t = {0};
    t.ReadIntervalTimeout = MAXDWORD;
    t.ReadTotalTimeoutMultiplier = MAXDWORD;
    t.ReadTotalTimeoutConstant = timeout_ms > 0 ? (DWORD)timeout_ms : 1;
    t.WriteTotalTimeoutConstant = 2000;
    if (!SetCommTimeouts(h, &t))
    {
        win_err(err, err_len, "Failed to set serial timeouts");
        return -1;
    }
    DWORD n = 0;
    if (!ReadFile(h, buf, (DWORD)len, &n, NULL))
    {
        win_err(err, err_len, "Failed to read from serial port");
        return -1;
    }
    return (int)n;
}

int hss_write(intptr_t handle, const uint8_t *buf, int len, char *err, int err_len)
{
    HANDLE h = (HANDLE)handle;
    int total = 0;
    while (total < len)
    {
        DWORD n = 0;
        if (!WriteFile(h, buf + total, (DWORD)(len - total), &n, NULL))
        {
            win_err(err, err_len, "Failed to write to serial port");
            return -1;
        }
        if (n == 0)
        {
            set_err(err, err_len, "Write to serial port timed out");
            return -1;
        }
        total += (int)n;
    }
    return total;
}

int hss_close(intptr_t handle)
{
    if (handle == HSS_INVALID_HANDLE)
        return -1;
    return CloseHandle((HANDLE)handle) ? 0 : -1;
}

#else
/* ======================================================================== */
/* POSIX (Linux, macOS)                                                     */
/* ======================================================================== */

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <IOKit/serial/ioss.h>
#endif

/* The termios constant for `baud`, or 0 if there is none. */
static speed_t baud_constant(int baud)
{
    switch (baud)
    {
    case 1200: return B1200;
    case 2400: return B2400;
    case 4800: return B4800;
    case 9600: return B9600;
    case 19200: return B19200;
    case 38400: return B38400;
    case 57600: return B57600;
    case 115200: return B115200;
    case 230400: return B230400;
#ifdef B460800
    case 460800: return B460800;
#endif
#ifdef B500000
    case 500000: return B500000;
#endif
#ifdef B921600
    case 921600: return B921600;
#endif
#ifdef B1000000
    case 1000000: return B1000000;
#endif
#ifdef B2000000
    case 2000000: return B2000000;
#endif
    default: return 0;
    }
}

intptr_t hss_open(const char *path, char *err, int err_len)
{
    return hss_open_baud(path, 0, err, err_len);
}

intptr_t hss_open_baud(const char *path, int baud, char *err, int err_len)
{
    if (baud <= 0)
        baud = 230400;
    speed_t speed = baud_constant(baud);
#if !defined(__APPLE__)
    if (speed == 0)
    {
        set_err(err, err_len, "Unsupported baud rate %d", baud);
        return HSS_INVALID_HANDLE;
    }
#endif
    /* O_NONBLOCK so open() does not wait for carrier detect (e.g. /dev/tty.* on macOS) */
    int fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (fd < 0)
    {
        set_err(err, err_len, "Failed to open serial port %s: %s", path, strerror(errno));
        return HSS_INVALID_HANDLE;
    }

    const char *what = NULL;
    int flags = fcntl(fd, F_GETFL, 0);
    struct termios tty;
    if (flags < 0 || fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) < 0)
        what = "Failed to set blocking mode";
    else if (ioctl(fd, TIOCEXCL) < 0)
        what = "Failed to get exclusive access";
    else if (tcgetattr(fd, &tty) != 0)
        what = "Failed to get serial parameters";

    if (what == NULL)
    {
        cfmakeraw(&tty);
        /* USB CDC ignores the baud rate. On macOS a rate without a constant
           is set with IOSSIOSPEED below. */
        speed_t standard = speed != 0 ? speed : B230400;
        cfsetispeed(&tty, standard);
        cfsetospeed(&tty, standard);
        tty.c_cflag &= ~(CSIZE | PARENB | CSTOPB | CRTSCTS | HUPCL);
        tty.c_cflag |= CS8 | CLOCAL | CREAD;
        tty.c_iflag &= ~(IXON | IXOFF | IXANY);
        tty.c_cc[VMIN] = 0;
        tty.c_cc[VTIME] = 0;
        if (tcsetattr(fd, TCSANOW, &tty) != 0)
            what = "Failed to set serial parameters";
#if defined(__APPLE__)
        else if (speed == 0)
        {
            speed_t any = (speed_t)baud;
            if (ioctl(fd, IOSSIOSPEED, &any) < 0)
                what = "Failed to set the baud rate";
        }
#endif
    }
    if (what != NULL)
    {
        set_err(err, err_len, "%s on %s: %s", what, path, strerror(errno));
        close(fd);
        return HSS_INVALID_HANDLE;
    }

    /* Disable DTR, as the upstream library does. Not supported by ptys, so errors are ignored. */
    int dtr = TIOCM_DTR;
    ioctl(fd, TIOCMBIC, &dtr);

    tcflush(fd, TCIOFLUSH);
    return (intptr_t)fd;
}

int hss_read(intptr_t handle, uint8_t *buf, int len, int timeout_ms, char *err, int err_len)
{
    int fd = (int)handle;
    struct pollfd pfd = {fd, POLLIN, 0};
    /* A signal (e.g. the Dart VM profiler's SIGPROF, every millisecond or
       so) interrupts poll(): wait for what is left of the timeout, or the
       wait never ends. */
    struct timespec start, now;
    clock_gettime(CLOCK_MONOTONIC, &start);
    int ret, left = timeout_ms;
    for (;;)
    {
        ret = poll(&pfd, 1, left);
        if (ret >= 0 || errno != EINTR)
            break;
        clock_gettime(CLOCK_MONOTONIC, &now);
        long spent = (long)(now.tv_sec - start.tv_sec) * 1000 +
                     (now.tv_nsec - start.tv_nsec) / 1000000;
        if (spent >= timeout_ms)
        {
            ret = 0;
            break;
        }
        left = timeout_ms - (int)spent;
    }

    if (ret < 0)
    {
        set_err(err, err_len, "Failed to wait for serial data: %s", strerror(errno));
        return -1;
    }
    if (ret == 0)
        return 0;
    if (pfd.revents & POLLIN)
    {
        ssize_t n;
        do
        {
            n = read(fd, buf, (size_t)len);
        } while (n < 0 && errno == EINTR);
        if (n > 0)
            return (int)n;
        if (n < 0 && errno == EAGAIN)
            return 0;
        if (n < 0)
        {
            set_err(err, err_len, "Failed to read from serial port: %s", strerror(errno));
            return -1;
        }
    }
    /* POLLHUP/POLLERR/POLLNVAL, or a zero-length read after POLLIN */
    set_err(err, err_len, "Serial device disconnected");
    return -1;
}

int hss_write(intptr_t handle, const uint8_t *buf, int len, char *err, int err_len)
{
    int fd = (int)handle;
    int total = 0;
    while (total < len)
    {
        ssize_t n = write(fd, buf + total, (size_t)(len - total));
        if (n < 0)
        {
            if (errno == EINTR)
                continue;
            if (errno == EAGAIN)
            {
                struct pollfd pfd = {fd, POLLOUT, 0};
                poll(&pfd, 1, 100);
                continue;
            }
            set_err(err, err_len, "Failed to write to serial port: %s", strerror(errno));
            return -1;
        }
        total += (int)n;
    }
    tcdrain(fd);
    return total;
}

int hss_close(intptr_t handle)
{
    if (handle == HSS_INVALID_HANDLE)
        return -1;
    return close((int)handle) == 0 ? 0 : -1;
}

#if defined(__APPLE__)
/* ------------------------------------------------------------------------ */
/* macOS port listing (IOKit)                                               */
/* ------------------------------------------------------------------------ */

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/serial/IOSerialKeys.h>
#include <IOKit/usb/USBSpec.h>

static int cf_string(CFTypeRef ref, char *out, int out_len)
{
    out[0] = '\0';
    if (ref == NULL || CFGetTypeID(ref) != CFStringGetTypeID())
        return 0;
    return CFStringGetCString((CFStringRef)ref, out, out_len, kCFStringEncodingUTF8) ? 1 : 0;
}

static CFTypeRef search_parents(io_object_t service, CFStringRef key)
{
    return IORegistryEntrySearchCFProperty(service, kIOServicePlane, key, kCFAllocatorDefault,
                                           kIORegistryIterateRecursively | kIORegistryIterateParents);
}

static void usb_id(io_object_t service, CFStringRef key, char *out)
{
    out[0] = '\0';
    CFTypeRef ref = search_parents(service, key);
    if (ref == NULL)
        return;
    int value = 0;
    if (CFGetTypeID(ref) == CFNumberGetTypeID() &&
        CFNumberGetValue((CFNumberRef)ref, kCFNumberIntType, &value))
        snprintf(out, 8, "%04x", value & 0xffff);
    CFRelease(ref);
}

int hss_list_ports(char *buf, int buf_len)
{
    out_buf_t out = {buf, buf_len, 0};
    if (buf != NULL && buf_len > 0)
        buf[0] = '\0';

    CFMutableDictionaryRef matching = IOServiceMatching(kIOSerialBSDServiceValue);
    if (matching == NULL)
        return -1;
    io_iterator_t iter = 0;
    /* Consumes the reference to matching */
    if (IOServiceGetMatchingServices(MACH_PORT_NULL, matching, &iter) != KERN_SUCCESS)
        return -1;

    io_object_t service;
    while ((service = IOIteratorNext(iter)) != 0)
    {
        char path[512];
        CFTypeRef callout = IORegistryEntryCreateCFProperty(service, CFSTR(kIOCalloutDeviceKey),
                                                            kCFAllocatorDefault, 0);
        int ok = cf_string(callout, path, sizeof(path));
        if (callout)
            CFRelease(callout);

        /* Only USB devices: they have a vendor id somewhere up the tree */
        char vid[8], pid[8];
        usb_id(service, CFSTR(kUSBVendorID), vid);
        usb_id(service, CFSTR(kUSBProductID), pid);

        if (ok && vid[0] != '\0')
        {
            /* The USB product string, the equivalent of the bus reported device description on Windows */
            char product[256] = "";
            const CFStringRef keys[] = {CFSTR("USB Product Name"), CFSTR("kUSBProductString")};
            for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); ++i)
            {
                CFTypeRef ref = search_parents(service, keys[i]);
                if (ref != NULL)
                {
                    cf_string(ref, product, sizeof(product));
                    CFRelease(ref);
                    break;
                }
            }
            out_port(&out, path, product, vid, pid, product);
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iter);
    return out.needed + 1;
}

#else
/* ------------------------------------------------------------------------ */
/* Linux port listing (sysfs)                                               */
/* ------------------------------------------------------------------------ */

#include <dirent.h>
#include <limits.h>

static int read_trimmed(const char *path, char *out, int out_len)
{
    out[0] = '\0';
    FILE *f = fopen(path, "r");
    if (f == NULL)
        return 0;
    if (fgets(out, out_len, f) == NULL)
        out[0] = '\0';
    fclose(f);
    size_t n = strlen(out);
    while (n > 0 && (out[n - 1] == '\n' || out[n - 1] == '\r' || out[n - 1] == ' ' || out[n - 1] == '\t'))
        out[--n] = '\0';
    return 1;
}

int hss_list_ports(char *buf, int buf_len)
{
    out_buf_t out = {buf, buf_len, 0};
    if (buf != NULL && buf_len > 0)
        buf[0] = '\0';

    DIR *dir = opendir("/sys/class/tty");
    if (dir == NULL)
        return -1;

    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL)
    {
        if (entry->d_name[0] == '.')
            continue;

        /* /sys/class/tty/<name>/device points at the USB interface; the USB device is a parent of that */
        char link[PATH_MAX], resolved[PATH_MAX];
        snprintf(link, sizeof(link), "/sys/class/tty/%s/device", entry->d_name);
        if (realpath(link, resolved) == NULL)
            continue; /* not backed by a physical device */

        char dev_dir[PATH_MAX];
        snprintf(dev_dir, sizeof(dev_dir), "%s", resolved);
        for (int i = 0; i < 4 && strlen(dev_dir) > 1; ++i)
        {
            char file[PATH_MAX + 16], vid[16], pid[16], product[256], manufacturer[256];
            snprintf(file, sizeof(file), "%s/idVendor", dev_dir);
            if (read_trimmed(file, vid, sizeof(vid)))
            {
                snprintf(file, sizeof(file), "%s/idProduct", dev_dir);
                read_trimmed(file, pid, sizeof(pid));
                snprintf(file, sizeof(file), "%s/product", dev_dir);
                read_trimmed(file, product, sizeof(product));
                snprintf(file, sizeof(file), "%s/manufacturer", dev_dir);
                read_trimmed(file, manufacturer, sizeof(manufacturer));

                char path[300], desc[520];
                snprintf(path, sizeof(path), "/dev/%s", entry->d_name);
                if (manufacturer[0] != '\0' && product[0] != '\0')
                    snprintf(desc, sizeof(desc), "%s %s", manufacturer, product);
                else
                    snprintf(desc, sizeof(desc), "%s", product[0] != '\0' ? product : entry->d_name);
                out_port(&out, path, desc, vid, pid, product);
                break;
            }
            char *slash = strrchr(dev_dir, '/');
            if (slash == NULL)
                break;
            *slash = '\0';
        }
    }
    closedir(dir);
    return out.needed + 1;
}

#endif /* __APPLE__ */
#endif /* _WIN32 */
