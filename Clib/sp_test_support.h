/*
 * sp_test_support.h - the platform calls simple_process's own tests make:
 * byte-exact standard stream copying for the echo child, a process probe,
 * a sleep and a clock. Tests only; nothing in src/ includes it.
 *
 * Stream arguments use the Windows codes: STD_INPUT_HANDLE (-10),
 * STD_OUTPUT_HANDLE (-11) and STD_ERROR_HANDLE (-12).
 *
 * Copyright (c) 2026 Larry Rix - MIT License
 */

#ifndef SP_TEST_SUPPORT_H
#define SP_TEST_SUPPORT_H

#include <string.h>

#if defined(_WIN32) || defined(EIF_WINDOWS)

#include <windows.h>

static void spt_copy(int a_from, int a_to)
{
    HANDLE l_in = GetStdHandle((DWORD) a_from);
    HANDLE l_out = GetStdHandle((DWORD) a_to);
    char l_buffer[65536];
    DWORD l_n = 0, l_w = 0, l_done = 0;
    while (ReadFile(l_in, l_buffer, sizeof(l_buffer), &l_n, NULL) && l_n > 0) {
        for (l_done = 0; l_done < l_n; l_done += l_w) {
            if (!WriteFile(l_out, l_buffer + l_done, l_n - l_done, &l_w, NULL) || l_w == 0) return;
        }
    }
}

static void spt_write_count(int a_to, const char* a_data, int a_count)
{
    DWORD l_w = 0, l_done = 0;
    while (l_done < (DWORD) a_count) {
        if (!WriteFile(GetStdHandle((DWORD) a_to), a_data + l_done, (DWORD) a_count - l_done, &l_w, NULL) || l_w == 0) return;
        l_done += l_w;
    }
}

static int spt_cat(void* a_path, int a_to, int a_chunk, int a_pause_ms)
{
    HANDLE l_file = CreateFileW((LPCWSTR) a_path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    HANDLE l_out = GetStdHandle((DWORD) a_to);
    char l_buffer[65536];
    DWORD l_n = 0, l_w = 0, l_done;
    DWORD l_chunk = (a_chunk > 0 && a_chunk < 65536) ? (DWORD) a_chunk : 65536;
    if (l_file == INVALID_HANDLE_VALUE) return 2;
    while (ReadFile(l_file, l_buffer, l_chunk, &l_n, NULL) && l_n > 0) {
        for (l_done = 0; l_done < l_n; l_done += l_w) {
            if (!WriteFile(l_out, l_buffer + l_done, l_n - l_done, &l_w, NULL) || l_w == 0) { CloseHandle(l_file); return 3; }
        }
        if (a_pause_ms > 0) Sleep((DWORD) a_pause_ms);
    }
    CloseHandle(l_file);
    return 0;
}

static int spt_pid_alive(unsigned int a_pid, int a_wait_ms)
{
    HANDLE l_h = OpenProcess(SYNCHRONIZE, FALSE, (DWORD) a_pid);
    DWORD l_r;
    if (!l_h) return 0;
    l_r = WaitForSingleObject(l_h, (DWORD) a_wait_ms);
    CloseHandle(l_h);
    return (l_r == WAIT_TIMEOUT) ? 1 : 0;
}

static void spt_kill_pid(unsigned int a_pid)
{
    HANDLE l_h = OpenProcess(PROCESS_TERMINATE, FALSE, (DWORD) a_pid);
    if (l_h) { TerminateProcess(l_h, 1); CloseHandle(l_h); }
}

static void spt_sleep_ms(int a_ms) { Sleep((DWORD) a_ms); }

static long long spt_now_ms(void)
{
    LARGE_INTEGER c, f;
    QueryPerformanceCounter(&c);
    QueryPerformanceFrequency(&f);
    return (c.QuadPart * 1000) / f.QuadPart;
}

#else  /* ============ POSIX ============ */

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

static int spt_fd(int a_code) { return a_code == -10 ? 0 : (a_code == -11 ? 1 : 2); }

static int spt_write_all(int a_fd, const char* a_data, size_t a_count)
{
    size_t l_done = 0;
    ssize_t l_w;
    while (l_done < a_count) {
        l_w = write(a_fd, a_data + l_done, a_count - l_done);
        if (l_w > 0) {
            l_done += (size_t) l_w;
        } else if (l_w == 0 || errno != EINTR) {
            return 0;
        }
    }
    return 1;
}

static void spt_copy(int a_from, int a_to)
{
    char l_buffer[65536];
    ssize_t l_n;
    for (;;) {
        l_n = read(spt_fd(a_from), l_buffer, sizeof(l_buffer));
        if (l_n < 0 && errno == EINTR) continue;
        if (l_n <= 0) return;
        if (!spt_write_all(spt_fd(a_to), l_buffer, (size_t) l_n)) return;
    }
}

static void spt_write_count(int a_to, const char* a_data, int a_count)
{
    spt_write_all(spt_fd(a_to), a_data, (size_t) a_count);
}

static void spt_sleep_ms(int a_ms)
{
    struct timespec l_left;
    l_left.tv_sec = a_ms / 1000;
    l_left.tv_nsec = (long) (a_ms % 1000) * 1000000L;
    while (nanosleep(&l_left, &l_left) != 0 && errno == EINTR) { }
}

static int spt_cat(void* a_path, int a_to, int a_chunk, int a_pause_ms)
{
    int l_file = open((const char*) a_path, O_RDONLY);
    char l_buffer[65536];
    size_t l_chunk = (a_chunk > 0 && a_chunk < 65536) ? (size_t) a_chunk : 65536;
    ssize_t l_n;
    if (l_file < 0) return 2;
    for (;;) {
        l_n = read(l_file, l_buffer, l_chunk);
        if (l_n < 0 && errno == EINTR) continue;
        if (l_n <= 0) break;
        if (!spt_write_all(spt_fd(a_to), l_buffer, (size_t) l_n)) { close(l_file); return 3; }
        if (a_pause_ms > 0) spt_sleep_ms(a_pause_ms);
    }
    close(l_file);
    return 0;
}

static int spt_pid_alive(unsigned int a_pid, int a_wait_ms)
{
    int l_waited = 0;
    for (;;) {
        if (kill((pid_t) a_pid, 0) != 0 && errno == ESRCH) return 0;
        if (l_waited >= a_wait_ms) return 1;
        spt_sleep_ms(10);
        l_waited += 10;
    }
}

static void spt_kill_pid(unsigned int a_pid) { kill((pid_t) a_pid, SIGKILL); }

static long long spt_now_ms(void)
{
    struct timespec l_now;
    clock_gettime(CLOCK_MONOTONIC, &l_now);
    return (long long) l_now.tv_sec * 1000 + l_now.tv_nsec / 1000000;
}

#endif

/* The same on every platform: a repeating pattern, in 4096-byte writes. */
static void spt_flood(int a_to, int a_count)
{
    char l_buffer[4096];
    int l_i, l_left = a_count, l_chunk;
    for (l_i = 0; l_i < 4096; l_i++) l_buffer[l_i] = (char) ('a' + (l_i % 26));
    while (l_left > 0) {
        l_chunk = l_left > 4096 ? 4096 : l_left;
        spt_write_count(a_to, l_buffer, l_chunk);
        l_left -= l_chunk;
    }
}

#endif /* SP_TEST_SUPPORT_H */
