#ifndef GM_THEOS_H
#define GM_THEOS_H
#include "runtime.h"

char *gm_theos_root(void);
int gm_theos_available(void);

int gm_theos_build(const char *project_path, const char *target, const char *arch,
                   const char *extra_flags,
                   GMRuntimeProgressFn cb, void *ctx,
                   char **out, int *code_out, char **err);
int gm_theos_clean(const char *project_path, char **out, int *code_out, char **err);
char *gm_theos_find_output(const char *project_path);

#endif
