#include "kazumi_rife_bridge.h"

#include <algorithm>
#include <cstdio>
#include <exception>
#include <memory>
#include <mutex>
#include <string>

#include "rife/rife.h"

namespace {

struct RifeContext {
  explicit RifeContext(std::unique_ptr<RIFE> instance)
      : rife(std::move(instance)) {}

  std::unique_ptr<RIFE> rife;
  std::mutex process_mutex;
};

std::mutex gpu_instance_mutex;
int gpu_instance_users = 0;

void set_error(char *buffer, size_t capacity, const char *message) {
  if (buffer == nullptr || capacity == 0) {
    return;
  }
  std::snprintf(buffer, capacity, "%s", message == nullptr ? "unknown error" : message);
}

bool acquire_gpu_instance(char *error, size_t error_capacity) {
  std::lock_guard<std::mutex> lock(gpu_instance_mutex);
  if (gpu_instance_users == 0) {
    ncnn::create_gpu_instance();
    if (ncnn::get_gpu_count() <= 0) {
      ncnn::destroy_gpu_instance();
      set_error(error, error_capacity, "no Vulkan compute device available");
      return false;
    }
  }
  ++gpu_instance_users;
  return true;
}

void release_gpu_instance() {
  std::lock_guard<std::mutex> lock(gpu_instance_mutex);
  if (gpu_instance_users <= 0) {
    return;
  }
  --gpu_instance_users;
  if (gpu_instance_users == 0) {
    ncnn::destroy_gpu_instance();
  }
}

}  // namespace

extern "C" int kazumi_rife_abi_version(void) {
  return KAZUMI_RIFE_ABI_VERSION;
}

extern "C" kazumi_rife_handle kazumi_rife_create(
    const char *model_directory,
    int gpu_id,
    char *error,
    size_t error_capacity) {
  if (model_directory == nullptr || model_directory[0] == '\0') {
    set_error(error, error_capacity, "model directory is empty");
    return nullptr;
  }
  if (!acquire_gpu_instance(error, error_capacity)) {
    return nullptr;
  }

  try {
    const int resolved_gpu_id =
        gpu_id < 0 ? ncnn::get_default_gpu_index() : gpu_id;
    if (resolved_gpu_id < 0 || resolved_gpu_id >= ncnn::get_gpu_count()) {
      set_error(error, error_capacity, "invalid Vulkan GPU id");
      release_gpu_instance();
      return nullptr;
    }

    // Practical-RIFE 4.25-lite uses the v4 graph and requires padding to 128.
    auto rife = std::make_unique<RIFE>(
        resolved_gpu_id,
        false,
        false,
        1,
        false,
        true,
        128);
    if (rife->load(std::string(model_directory)) != 0) {
      set_error(error, error_capacity, "failed to load RIFE model");
      release_gpu_instance();
      return nullptr;
    }

    return new RifeContext(std::move(rife));
  } catch (const std::exception &exception) {
    set_error(error, error_capacity, exception.what());
  } catch (...) {
    set_error(error, error_capacity, "unexpected RIFE initialization error");
  }

  release_gpu_instance();
  return nullptr;
}

extern "C" int kazumi_rife_process(
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
  auto *context = static_cast<RifeContext *>(handle);
  if (context == nullptr || context->rife == nullptr) {
    set_error(error, error_capacity, "RIFE context is not initialized");
    return -1;
  }
  if (width <= 0 || height <= 0 || stride < width) {
    set_error(error, error_capacity, "invalid frame dimensions or stride");
    return -2;
  }
  if (!(timestep > 0.0F && timestep < 1.0F)) {
    set_error(error, error_capacity, "timestep must be between 0 and 1");
    return -3;
  }
  if (src0_r == nullptr || src0_g == nullptr || src0_b == nullptr ||
      src1_r == nullptr || src1_g == nullptr || src1_b == nullptr ||
      dst_r == nullptr || dst_g == nullptr || dst_b == nullptr) {
    set_error(error, error_capacity, "frame plane is null");
    return -4;
  }

  try {
    std::lock_guard<std::mutex> lock(context->process_mutex);
    const int result = context->rife->process(
        src0_r,
        src0_g,
        src0_b,
        src1_r,
        src1_g,
        src1_b,
        dst_r,
        dst_g,
        dst_b,
        width,
        height,
        stride,
        timestep);
    if (result != 0) {
      set_error(error, error_capacity, "RIFE inference failed");
    }
    return result;
  } catch (const std::exception &exception) {
    set_error(error, error_capacity, exception.what());
  } catch (...) {
    set_error(error, error_capacity, "unexpected RIFE inference error");
  }
  return -5;
}

extern "C" void kazumi_rife_destroy(kazumi_rife_handle handle) {
  auto *context = static_cast<RifeContext *>(handle);
  if (context == nullptr) {
    return;
  }
  delete context;
  release_gpu_instance();
}
