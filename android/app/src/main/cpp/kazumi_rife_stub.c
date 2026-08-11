#include "kazumi_rife_bridge.h"

#include <stdio.h>

int kazumi_rife_abi_version(void) {
  return KAZUMI_RIFE_ABI_VERSION;
}

kazumi_rife_handle kazumi_rife_create(
    const char *model_directory,
    int gpu_id,
    char *error,
    size_t error_capacity) {
  (void)model_directory;
  (void)gpu_id;
  if (error != NULL && error_capacity > 0) {
    snprintf(error, error_capacity, "RIFE is only available on arm64-v8a");
  }
  return NULL;
}

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
    size_t error_capacity) {
  (void)handle;
  (void)src0_r;
  (void)src0_g;
  (void)src0_b;
  (void)src1_r;
  (void)src1_g;
  (void)src1_b;
  (void)dst_r;
  (void)dst_g;
  (void)dst_b;
  (void)width;
  (void)height;
  (void)stride;
  (void)timestep;
  if (error != NULL && error_capacity > 0) {
    snprintf(error, error_capacity, "RIFE is only available on arm64-v8a");
  }
  return -1;
}

int kazumi_rife_process_pair(
    kazumi_rife_handle handle,
    const float *src0_r,
    const float *src0_g,
    const float *src0_b,
    const float *src1_r,
    const float *src1_g,
    const float *src1_b,
    float *dst1_r,
    float *dst1_g,
    float *dst1_b,
    float *dst2_r,
    float *dst2_g,
    float *dst2_b,
    int width,
    int height,
    ptrdiff_t stride,
    char *error,
    size_t error_capacity) {
  (void)handle;
  (void)src0_r;
  (void)src0_g;
  (void)src0_b;
  (void)src1_r;
  (void)src1_g;
  (void)src1_b;
  (void)dst1_r;
  (void)dst1_g;
  (void)dst1_b;
  (void)dst2_r;
  (void)dst2_g;
  (void)dst2_b;
  (void)width;
  (void)height;
  (void)stride;
  if (error != NULL && error_capacity > 0) {
    snprintf(error, error_capacity, "RIFE is only available on arm64-v8a");
  }
  return -1;
}

void kazumi_rife_destroy(kazumi_rife_handle handle) {
  (void)handle;
}
