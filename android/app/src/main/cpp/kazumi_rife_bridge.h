#ifndef KAZUMI_RIFE_BRIDGE_H
#define KAZUMI_RIFE_BRIDGE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define KAZUMI_RIFE_ABI_VERSION 1

typedef void *kazumi_rife_handle;

int kazumi_rife_abi_version(void);

kazumi_rife_handle kazumi_rife_create(
    const char *model_directory,
    int gpu_id,
    char *error,
    size_t error_capacity);

int kazumi_rife_process(
    kazumi_rife_handle handle,
    const float *src0_r,
    const float *src0_g,
    const float *src0_b,
    const float *src1_r,
    const float *src1_g,
    const float *src1_b,
    float *dst_r,
    float *dst_g,
    float *dst_b,
    int width,
    int height,
    ptrdiff_t stride,
    float timestep,
    char *error,
    size_t error_capacity);

void kazumi_rife_destroy(kazumi_rife_handle handle);

#ifdef __cplusplus
}
#endif

#endif
