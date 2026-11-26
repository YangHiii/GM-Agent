/* GM Agent · 引擎日志（线程安全，写文件 + stderr） */
#include "gm_engine.h"
#include <pthread.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>

static int g_logFd = -1;
static pthread_mutex_t g_logLock = PTHREAD_MUTEX_INITIALIZER;

void gm_log_init(void) {
    const char *path = getenv("GM_LOG_FILE");
    if (!path || !*path) return;
    g_logFd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
}

void gm_logf(const char *fmt, ...) {
    char msg[2048];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(msg, sizeof(msg), fmt, ap);
    va_end(ap);

    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    struct tm tmv;
    localtime_r(&ts.tv_sec, &tmv);
    char line[2300];
    int n = snprintf(line, sizeof(line), "%02d:%02d:%02d.%03d [engine] %s\n",
                     tmv.tm_hour, tmv.tm_min, tmv.tm_sec, (int)(ts.tv_nsec / 1000000), msg);

    pthread_mutex_lock(&g_logLock);
    fprintf(stderr, "%s", line);
    if (g_logFd >= 0 && n > 0) {
        ssize_t w = write(g_logFd, line, (size_t)n);
        (void)w;
    }
    pthread_mutex_unlock(&g_logLock);
}
