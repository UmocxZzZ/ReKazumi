#include "rekazumi_offscreen.h"

#include <vulkan/vulkan.h>

#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "framegen_offscreen_spv.h"

namespace rekazumi {
namespace {

constexpr char kValidationMarker[] =
    "ReKazumi Vulkan offscreen phase validation v1";
constexpr char kTimeoutPolicyMarker[] =
    "ReKazumi offscreen timeout quarantine v1";
constexpr uint32_t kWidth = 8;
constexpr uint32_t kHeight = 8;
constexpr VkDeviceSize kOutputBytes =
    static_cast<VkDeviceSize>(kWidth) * kHeight * 4 * sizeof(uint16_t);
constexpr uint64_t kFenceTimeoutNanoseconds = 5'000'000'000ULL;

struct ImageResource {
  VkImage image = VK_NULL_HANDLE;
  VkDeviceMemory memory = VK_NULL_HANDLE;
  VkImageView view = VK_NULL_HANDLE;
};

struct BufferResource {
  VkBuffer buffer = VK_NULL_HANDLE;
  VkDeviceMemory memory = VK_NULL_HANDLE;
};

struct ValidationReport {
  bool complete = false;
  bool rgba16f_ready = false;
  bool rg16f_ready = false;
  bool shader_executed = false;
  bool phase_13_valid = false;
  bool phase_23_valid = false;
  bool resources_quarantined = false;
  uint64_t phase_13_gpu_ns = 0;
  uint64_t phase_23_gpu_ns = 0;
  float phase_13_red = 0.0F;
  float phase_23_red = 0.0F;
  std::string device_name;
  std::string error;
};

struct ValidationContext {
  VkInstance instance = VK_NULL_HANDLE;
  VkPhysicalDevice physical_device = VK_NULL_HANDLE;
  VkPhysicalDeviceMemoryProperties memory_properties{};
  VkDevice device = VK_NULL_HANDLE;
  VkQueue queue = VK_NULL_HANDLE;
  uint32_t queue_family = 0;
  uint32_t timestamp_valid_bits = 0;
  float timestamp_period = 0.0F;
  VkDescriptorSetLayout descriptor_set_layout = VK_NULL_HANDLE;
  VkPipelineLayout pipeline_layout = VK_NULL_HANDLE;
  VkShaderModule shader_module = VK_NULL_HANDLE;
  VkPipeline pipeline = VK_NULL_HANDLE;
  VkDescriptorPool descriptor_pool = VK_NULL_HANDLE;
  std::array<VkDescriptorSet, 2> descriptor_sets{};
  VkCommandPool command_pool = VK_NULL_HANDLE;
  VkCommandBuffer command_buffer = VK_NULL_HANDLE;
  VkQueryPool query_pool = VK_NULL_HANDLE;
  VkFence fence = VK_NULL_HANDLE;
  std::array<ImageResource, 4> images{};
  std::array<BufferResource, 2> buffers{};
  bool abandon_resources = false;

  ~ValidationContext() {
    if (abandon_resources) {
      return;
    }
    if (device != VK_NULL_HANDLE) {
      if (fence != VK_NULL_HANDLE) {
        vkDestroyFence(device, fence, nullptr);
      }
      if (query_pool != VK_NULL_HANDLE) {
        vkDestroyQueryPool(device, query_pool, nullptr);
      }
      if (command_pool != VK_NULL_HANDLE) {
        vkDestroyCommandPool(device, command_pool, nullptr);
      }
      if (descriptor_pool != VK_NULL_HANDLE) {
        vkDestroyDescriptorPool(device, descriptor_pool, nullptr);
      }
      if (pipeline != VK_NULL_HANDLE) {
        vkDestroyPipeline(device, pipeline, nullptr);
      }
      if (shader_module != VK_NULL_HANDLE) {
        vkDestroyShaderModule(device, shader_module, nullptr);
      }
      if (pipeline_layout != VK_NULL_HANDLE) {
        vkDestroyPipelineLayout(device, pipeline_layout, nullptr);
      }
      if (descriptor_set_layout != VK_NULL_HANDLE) {
        vkDestroyDescriptorSetLayout(device, descriptor_set_layout, nullptr);
      }
      for (auto &buffer : buffers) {
        if (buffer.buffer != VK_NULL_HANDLE) {
          vkDestroyBuffer(device, buffer.buffer, nullptr);
        }
        if (buffer.memory != VK_NULL_HANDLE) {
          vkFreeMemory(device, buffer.memory, nullptr);
        }
      }
      for (auto &image : images) {
        if (image.view != VK_NULL_HANDLE) {
          vkDestroyImageView(device, image.view, nullptr);
        }
        if (image.image != VK_NULL_HANDLE) {
          vkDestroyImage(device, image.image, nullptr);
        }
        if (image.memory != VK_NULL_HANDLE) {
          vkFreeMemory(device, image.memory, nullptr);
        }
      }
      vkDestroyDevice(device, nullptr);
    }
    if (instance != VK_NULL_HANDLE) {
      vkDestroyInstance(instance, nullptr);
    }
  }
};

void Check(VkResult result, const char *stage) {
  if (result != VK_SUCCESS) {
    throw std::runtime_error(std::string(stage) + "_" +
                             std::to_string(static_cast<int>(result)));
  }
}

std::string EscapeJson(const std::string &value) {
  std::ostringstream output;
  for (const unsigned char character : value) {
    switch (character) {
    case '\\':
      output << "\\\\";
      break;
    case '"':
      output << "\\\"";
      break;
    case '\n':
      output << "\\n";
      break;
    case '\r':
      output << "\\r";
      break;
    case '\t':
      output << "\\t";
      break;
    default:
      if (character < 0x20) {
        output << '?';
      } else {
        output << static_cast<char>(character);
      }
      break;
    }
  }
  return output.str();
}

std::string BuildJson(const ValidationReport &report) {
  std::ostringstream json;
  json << '{' << "\"validationMarker\":\"" << kValidationMarker << "\","
       << "\"shaderSha256\":\"" << kFramegenOffscreenShaderSha256 << "\","
       << "\"timeoutPolicyMarker\":\"" << kTimeoutPolicyMarker << "\","
       << "\"validationComplete\":" << (report.complete ? "true" : "false")
       << ',' << "\"noSurface\":true,"
       << "\"rgba16fReady\":" << (report.rgba16f_ready ? "true" : "false")
       << ',' << "\"rg16fReady\":" << (report.rg16f_ready ? "true" : "false")
       << ','
       << "\"shaderExecuted\":" << (report.shader_executed ? "true" : "false")
       << ','
       << "\"phase13Valid\":" << (report.phase_13_valid ? "true" : "false")
       << ','
       << "\"phase23Valid\":" << (report.phase_23_valid ? "true" : "false")
       << ',' << "\"resourcesQuarantined\":"
       << (report.resources_quarantined ? "true" : "false") << ','
       << "\"phase13GpuNs\":" << report.phase_13_gpu_ns << ','
       << "\"phase23GpuNs\":" << report.phase_23_gpu_ns << ','
       << "\"phase13Red\":" << report.phase_13_red << ','
       << "\"phase23Red\":" << report.phase_23_red << ',' << "\"deviceName\":\""
       << EscapeJson(report.device_name) << "\","
       << "\"transportBackendImplemented\":false," << "\"error\":\""
       << EscapeJson(report.error) << "\"}";
  return json.str();
}

bool HasFormatFeatures(VkPhysicalDevice device, VkFormat format,
                       VkFormatFeatureFlags required) {
  VkFormatProperties properties{};
  vkGetPhysicalDeviceFormatProperties(device, format, &properties);
  return (properties.optimalTilingFeatures & required) == required;
}

void CreateInstance(ValidationContext &context) {
  uint32_t loader_version = VK_API_VERSION_1_0;
  const auto enumerate_instance_version =
      reinterpret_cast<PFN_vkEnumerateInstanceVersion>(
          vkGetInstanceProcAddr(VK_NULL_HANDLE, "vkEnumerateInstanceVersion"));
  if (enumerate_instance_version != nullptr) {
    Check(enumerate_instance_version(&loader_version),
          "vkEnumerateInstanceVersion_failed");
  }
  if (loader_version < VK_API_VERSION_1_1) {
    throw std::runtime_error("vulkan_1_1_loader_unavailable");
  }

  VkApplicationInfo application_info{};
  application_info.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
  application_info.pApplicationName = "ReKazumi";
  application_info.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
  application_info.pEngineName = "ReKazumi offscreen validation";
  application_info.engineVersion = VK_MAKE_VERSION(1, 0, 0);
  application_info.apiVersion = VK_API_VERSION_1_1;

  VkInstanceCreateInfo create_info{};
  create_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
  create_info.pApplicationInfo = &application_info;
  Check(vkCreateInstance(&create_info, nullptr, &context.instance),
        "vkCreateInstance_failed");
}

void SelectPhysicalDevice(ValidationContext &context,
                          ValidationReport &report) {
  uint32_t device_count = 0;
  Check(vkEnumeratePhysicalDevices(context.instance, &device_count, nullptr),
        "vkEnumeratePhysicalDevices_count_failed");
  if (device_count == 0) {
    throw std::runtime_error("no_physical_device");
  }
  std::vector<VkPhysicalDevice> devices(device_count);
  Check(vkEnumeratePhysicalDevices(context.instance, &device_count,
                                   devices.data()),
        "vkEnumeratePhysicalDevices_failed");

  constexpr VkFormatFeatureFlags rgba_required =
      VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT |
      VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT | VK_FORMAT_FEATURE_TRANSFER_SRC_BIT |
      VK_FORMAT_FEATURE_TRANSFER_DST_BIT;
  constexpr VkFormatFeatureFlags rg_required =
      VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT | VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT;

  for (VkPhysicalDevice device : devices) {
    VkPhysicalDeviceProperties properties{};
    vkGetPhysicalDeviceProperties(device, &properties);
    if (properties.apiVersion < VK_API_VERSION_1_1 ||
        properties.limits.timestampComputeAndGraphics != VK_TRUE) {
      continue;
    }

    const bool rgba_ready =
        HasFormatFeatures(device, VK_FORMAT_R16G16B16A16_SFLOAT, rgba_required);
    const bool rg_ready =
        HasFormatFeatures(device, VK_FORMAT_R16G16_SFLOAT, rg_required);
    if (!rgba_ready || !rg_ready) {
      continue;
    }

    uint32_t queue_count = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_count, nullptr);
    std::vector<VkQueueFamilyProperties> queues(queue_count);
    vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_count,
                                             queues.data());
    for (uint32_t index = 0; index < queue_count; ++index) {
      if ((queues[index].queueFlags & VK_QUEUE_COMPUTE_BIT) == 0 ||
          queues[index].timestampValidBits == 0) {
        continue;
      }
      context.physical_device = device;
      context.queue_family = index;
      context.timestamp_valid_bits = queues[index].timestampValidBits;
      context.timestamp_period = properties.limits.timestampPeriod;
      vkGetPhysicalDeviceMemoryProperties(device, &context.memory_properties);
      report.device_name = properties.deviceName;
      report.rgba16f_ready = true;
      report.rg16f_ready = true;
      return;
    }
  }
  throw std::runtime_error("no_compute_device_with_required_formats");
}

void CreateDevice(ValidationContext &context) {
  constexpr float queue_priority = 1.0F;
  VkDeviceQueueCreateInfo queue_info{};
  queue_info.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
  queue_info.queueFamilyIndex = context.queue_family;
  queue_info.queueCount = 1;
  queue_info.pQueuePriorities = &queue_priority;

  VkDeviceCreateInfo create_info{};
  create_info.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
  create_info.queueCreateInfoCount = 1;
  create_info.pQueueCreateInfos = &queue_info;
  Check(vkCreateDevice(context.physical_device, &create_info, nullptr,
                       &context.device),
        "vkCreateDevice_failed");
  vkGetDeviceQueue(context.device, context.queue_family, 0, &context.queue);
  if (context.queue == VK_NULL_HANDLE) {
    throw std::runtime_error("vkGetDeviceQueue_returned_null");
  }
}

uint32_t FindMemoryType(const ValidationContext &context,
                        uint32_t compatible_types,
                        VkMemoryPropertyFlags required) {
  for (uint32_t index = 0; index < context.memory_properties.memoryTypeCount;
       ++index) {
    const bool compatible = (compatible_types & (1U << index)) != 0;
    const bool has_properties =
        (context.memory_properties.memoryTypes[index].propertyFlags &
         required) == required;
    if (compatible && has_properties) {
      return index;
    }
  }
  throw std::runtime_error("compatible_memory_type_unavailable");
}

void CreateImage(ValidationContext &context, ImageResource &resource) {
  VkImageCreateInfo image_info{};
  image_info.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
  image_info.imageType = VK_IMAGE_TYPE_2D;
  image_info.format = VK_FORMAT_R16G16B16A16_SFLOAT;
  image_info.extent = {kWidth, kHeight, 1};
  image_info.mipLevels = 1;
  image_info.arrayLayers = 1;
  image_info.samples = VK_SAMPLE_COUNT_1_BIT;
  image_info.tiling = VK_IMAGE_TILING_OPTIMAL;
  image_info.usage = VK_IMAGE_USAGE_STORAGE_BIT |
                     VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
                     VK_IMAGE_USAGE_TRANSFER_DST_BIT;
  image_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
  image_info.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
  Check(vkCreateImage(context.device, &image_info, nullptr, &resource.image),
        "vkCreateImage_failed");

  VkMemoryRequirements requirements{};
  vkGetImageMemoryRequirements(context.device, resource.image, &requirements);
  VkMemoryAllocateInfo allocation_info{};
  allocation_info.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
  allocation_info.allocationSize = requirements.size;
  allocation_info.memoryTypeIndex =
      FindMemoryType(context, requirements.memoryTypeBits,
                     VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
  Check(vkAllocateMemory(context.device, &allocation_info, nullptr,
                         &resource.memory),
        "vkAllocateImageMemory_failed");
  Check(vkBindImageMemory(context.device, resource.image, resource.memory, 0),
        "vkBindImageMemory_failed");

  VkImageViewCreateInfo view_info{};
  view_info.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
  view_info.image = resource.image;
  view_info.viewType = VK_IMAGE_VIEW_TYPE_2D;
  view_info.format = image_info.format;
  view_info.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
  view_info.subresourceRange.levelCount = 1;
  view_info.subresourceRange.layerCount = 1;
  Check(vkCreateImageView(context.device, &view_info, nullptr, &resource.view),
        "vkCreateImageView_failed");
}

void CreateBuffer(ValidationContext &context, BufferResource &resource) {
  VkBufferCreateInfo buffer_info{};
  buffer_info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
  buffer_info.size = kOutputBytes;
  buffer_info.usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT;
  buffer_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
  Check(vkCreateBuffer(context.device, &buffer_info, nullptr, &resource.buffer),
        "vkCreateBuffer_failed");

  VkMemoryRequirements requirements{};
  vkGetBufferMemoryRequirements(context.device, resource.buffer, &requirements);
  VkMemoryAllocateInfo allocation_info{};
  allocation_info.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
  allocation_info.allocationSize = requirements.size;
  allocation_info.memoryTypeIndex =
      FindMemoryType(context, requirements.memoryTypeBits,
                     VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                         VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
  Check(vkAllocateMemory(context.device, &allocation_info, nullptr,
                         &resource.memory),
        "vkAllocateBufferMemory_failed");
  Check(vkBindBufferMemory(context.device, resource.buffer, resource.memory, 0),
        "vkBindBufferMemory_failed");
}

void CreatePipeline(ValidationContext &context) {
  std::array<VkDescriptorSetLayoutBinding, 3> bindings{};
  for (uint32_t index = 0; index < bindings.size(); ++index) {
    bindings[index].binding = index;
    bindings[index].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
    bindings[index].descriptorCount = 1;
    bindings[index].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
  }
  VkDescriptorSetLayoutCreateInfo set_layout_info{};
  set_layout_info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
  set_layout_info.bindingCount = static_cast<uint32_t>(bindings.size());
  set_layout_info.pBindings = bindings.data();
  Check(vkCreateDescriptorSetLayout(context.device, &set_layout_info, nullptr,
                                    &context.descriptor_set_layout),
        "vkCreateDescriptorSetLayout_failed");

  VkPushConstantRange push_constant{};
  push_constant.stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
  push_constant.offset = 0;
  push_constant.size = sizeof(float);
  VkPipelineLayoutCreateInfo pipeline_layout_info{};
  pipeline_layout_info.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
  pipeline_layout_info.setLayoutCount = 1;
  pipeline_layout_info.pSetLayouts = &context.descriptor_set_layout;
  pipeline_layout_info.pushConstantRangeCount = 1;
  pipeline_layout_info.pPushConstantRanges = &push_constant;
  Check(vkCreatePipelineLayout(context.device, &pipeline_layout_info, nullptr,
                               &context.pipeline_layout),
        "vkCreatePipelineLayout_failed");

  VkShaderModuleCreateInfo shader_info{};
  shader_info.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
  shader_info.codeSize = kFramegenOffscreenSpirvSize;
  shader_info.pCode = kFramegenOffscreenSpirv;
  Check(vkCreateShaderModule(context.device, &shader_info, nullptr,
                             &context.shader_module),
        "vkCreateShaderModule_failed");

  VkComputePipelineCreateInfo pipeline_info{};
  pipeline_info.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
  pipeline_info.stage.sType =
      VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
  pipeline_info.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
  pipeline_info.stage.module = context.shader_module;
  pipeline_info.stage.pName = "main";
  pipeline_info.layout = context.pipeline_layout;
  Check(vkCreateComputePipelines(context.device, VK_NULL_HANDLE, 1,
                                 &pipeline_info, nullptr, &context.pipeline),
        "vkCreateComputePipelines_failed");
}

void CreateDescriptors(ValidationContext &context) {
  VkDescriptorPoolSize pool_size{};
  pool_size.type = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
  pool_size.descriptorCount = 6;
  VkDescriptorPoolCreateInfo pool_info{};
  pool_info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
  pool_info.maxSets = 2;
  pool_info.poolSizeCount = 1;
  pool_info.pPoolSizes = &pool_size;
  Check(vkCreateDescriptorPool(context.device, &pool_info, nullptr,
                               &context.descriptor_pool),
        "vkCreateDescriptorPool_failed");

  std::array<VkDescriptorSetLayout, 2> layouts = {
      context.descriptor_set_layout, context.descriptor_set_layout};
  VkDescriptorSetAllocateInfo allocate_info{};
  allocate_info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
  allocate_info.descriptorPool = context.descriptor_pool;
  allocate_info.descriptorSetCount = static_cast<uint32_t>(layouts.size());
  allocate_info.pSetLayouts = layouts.data();
  Check(vkAllocateDescriptorSets(context.device, &allocate_info,
                                 context.descriptor_sets.data()),
        "vkAllocateDescriptorSets_failed");

  for (uint32_t set_index = 0; set_index < 2; ++set_index) {
    std::array<VkDescriptorImageInfo, 3> image_infos{};
    image_infos[0].imageView = context.images[0].view;
    image_infos[1].imageView = context.images[1].view;
    image_infos[2].imageView = context.images[2 + set_index].view;
    for (auto &image_info : image_infos) {
      image_info.imageLayout = VK_IMAGE_LAYOUT_GENERAL;
    }
    std::array<VkWriteDescriptorSet, 3> writes{};
    for (uint32_t binding = 0; binding < writes.size(); ++binding) {
      writes[binding].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
      writes[binding].dstSet = context.descriptor_sets[set_index];
      writes[binding].dstBinding = binding;
      writes[binding].descriptorCount = 1;
      writes[binding].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
      writes[binding].pImageInfo = &image_infos[binding];
    }
    vkUpdateDescriptorSets(context.device, static_cast<uint32_t>(writes.size()),
                           writes.data(), 0, nullptr);
  }
}

void CreateCommandsAndQueries(ValidationContext &context) {
  VkCommandPoolCreateInfo pool_info{};
  pool_info.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
  pool_info.queueFamilyIndex = context.queue_family;
  pool_info.flags = VK_COMMAND_POOL_CREATE_TRANSIENT_BIT;
  Check(vkCreateCommandPool(context.device, &pool_info, nullptr,
                            &context.command_pool),
        "vkCreateCommandPool_failed");

  VkCommandBufferAllocateInfo allocate_info{};
  allocate_info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
  allocate_info.commandPool = context.command_pool;
  allocate_info.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
  allocate_info.commandBufferCount = 1;
  Check(vkAllocateCommandBuffers(context.device, &allocate_info,
                                 &context.command_buffer),
        "vkAllocateCommandBuffers_failed");

  VkQueryPoolCreateInfo query_info{};
  query_info.sType = VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO;
  query_info.queryType = VK_QUERY_TYPE_TIMESTAMP;
  query_info.queryCount = 4;
  Check(vkCreateQueryPool(context.device, &query_info, nullptr,
                          &context.query_pool),
        "vkCreateQueryPool_failed");

  VkFenceCreateInfo fence_info{};
  fence_info.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
  Check(vkCreateFence(context.device, &fence_info, nullptr, &context.fence),
        "vkCreateFence_failed");
}

VkImageMemoryBarrier ImageBarrier(VkImage image, VkImageLayout old_layout,
                                  VkImageLayout new_layout,
                                  VkAccessFlags source_access,
                                  VkAccessFlags destination_access) {
  VkImageMemoryBarrier barrier{};
  barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
  barrier.srcAccessMask = source_access;
  barrier.dstAccessMask = destination_access;
  barrier.oldLayout = old_layout;
  barrier.newLayout = new_layout;
  barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
  barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
  barrier.image = image;
  barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
  barrier.subresourceRange.levelCount = 1;
  barrier.subresourceRange.layerCount = 1;
  return barrier;
}

void RecordCommands(ValidationContext &context) {
  VkCommandBufferBeginInfo begin_info{};
  begin_info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
  begin_info.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
  Check(vkBeginCommandBuffer(context.command_buffer, &begin_info),
        "vkBeginCommandBuffer_failed");
  vkCmdResetQueryPool(context.command_buffer, context.query_pool, 0, 4);

  std::array<VkImageMemoryBarrier, 4> initial_barriers{};
  for (uint32_t index = 0; index < initial_barriers.size(); ++index) {
    initial_barriers[index] = ImageBarrier(
        context.images[index].image, VK_IMAGE_LAYOUT_UNDEFINED,
        VK_IMAGE_LAYOUT_GENERAL, 0,
        index < 2 ? VK_ACCESS_TRANSFER_WRITE_BIT : VK_ACCESS_SHADER_WRITE_BIT);
  }
  vkCmdPipelineBarrier(
      context.command_buffer, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
      VK_PIPELINE_STAGE_TRANSFER_BIT | VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0,
      0, nullptr, 0, nullptr, static_cast<uint32_t>(initial_barriers.size()),
      initial_barriers.data());

  VkImageSubresourceRange color_range{};
  color_range.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
  color_range.levelCount = 1;
  color_range.layerCount = 1;
  VkClearColorValue source_a{};
  source_a.float32[3] = 1.0F;
  VkClearColorValue source_b{};
  source_b.float32[0] = 1.0F;
  source_b.float32[1] = 0.5F;
  source_b.float32[2] = 0.25F;
  source_b.float32[3] = 1.0F;
  vkCmdClearColorImage(context.command_buffer, context.images[0].image,
                       VK_IMAGE_LAYOUT_GENERAL, &source_a, 1, &color_range);
  vkCmdClearColorImage(context.command_buffer, context.images[1].image,
                       VK_IMAGE_LAYOUT_GENERAL, &source_b, 1, &color_range);

  std::array<VkImageMemoryBarrier, 2> source_barriers = {
      ImageBarrier(context.images[0].image, VK_IMAGE_LAYOUT_GENERAL,
                   VK_IMAGE_LAYOUT_GENERAL, VK_ACCESS_TRANSFER_WRITE_BIT,
                   VK_ACCESS_SHADER_READ_BIT),
      ImageBarrier(context.images[1].image, VK_IMAGE_LAYOUT_GENERAL,
                   VK_IMAGE_LAYOUT_GENERAL, VK_ACCESS_TRANSFER_WRITE_BIT,
                   VK_ACCESS_SHADER_READ_BIT)};
  vkCmdPipelineBarrier(context.command_buffer, VK_PIPELINE_STAGE_TRANSFER_BIT,
                       VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, nullptr, 0,
                       nullptr, static_cast<uint32_t>(source_barriers.size()),
                       source_barriers.data());

  vkCmdBindPipeline(context.command_buffer, VK_PIPELINE_BIND_POINT_COMPUTE,
                    context.pipeline);
  constexpr std::array<float, 2> phases = {1.0F / 3.0F, 2.0F / 3.0F};
  for (uint32_t index = 0; index < phases.size(); ++index) {
    vkCmdBindDescriptorSets(context.command_buffer,
                            VK_PIPELINE_BIND_POINT_COMPUTE,
                            context.pipeline_layout, 0, 1,
                            &context.descriptor_sets[index], 0, nullptr);
    vkCmdPushConstants(context.command_buffer, context.pipeline_layout,
                       VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(float),
                       &phases[index]);
    vkCmdWriteTimestamp(context.command_buffer,
                        VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                        context.query_pool, index * 2);
    vkCmdDispatch(context.command_buffer, 1, 1, 1);
    vkCmdWriteTimestamp(context.command_buffer,
                        VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                        context.query_pool, index * 2 + 1);
  }

  std::array<VkImageMemoryBarrier, 2> output_barriers = {
      ImageBarrier(context.images[2].image, VK_IMAGE_LAYOUT_GENERAL,
                   VK_IMAGE_LAYOUT_GENERAL, VK_ACCESS_SHADER_WRITE_BIT,
                   VK_ACCESS_TRANSFER_READ_BIT),
      ImageBarrier(context.images[3].image, VK_IMAGE_LAYOUT_GENERAL,
                   VK_IMAGE_LAYOUT_GENERAL, VK_ACCESS_SHADER_WRITE_BIT,
                   VK_ACCESS_TRANSFER_READ_BIT)};
  vkCmdPipelineBarrier(
      context.command_buffer, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
      VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr,
      static_cast<uint32_t>(output_barriers.size()), output_barriers.data());

  VkBufferImageCopy copy{};
  copy.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
  copy.imageSubresource.layerCount = 1;
  copy.imageExtent = {kWidth, kHeight, 1};
  for (uint32_t index = 0; index < 2; ++index) {
    vkCmdCopyImageToBuffer(
        context.command_buffer, context.images[2 + index].image,
        VK_IMAGE_LAYOUT_GENERAL, context.buffers[index].buffer, 1, &copy);
  }
  Check(vkEndCommandBuffer(context.command_buffer),
        "vkEndCommandBuffer_failed");
}

float HalfToFloat(uint16_t half) {
  const uint32_t sign = static_cast<uint32_t>(half & 0x8000U) << 16U;
  uint32_t exponent = (half >> 10U) & 0x1FU;
  uint32_t mantissa = half & 0x03FFU;
  uint32_t bits = 0;
  if (exponent == 0) {
    if (mantissa == 0) {
      bits = sign;
    } else {
      int shift = 0;
      while ((mantissa & 0x0400U) == 0) {
        mantissa <<= 1U;
        ++shift;
      }
      mantissa &= 0x03FFU;
      const uint32_t float_exponent = static_cast<uint32_t>(127 - 15 - shift);
      bits = sign | (float_exponent << 23U) | (mantissa << 13U);
    }
  } else if (exponent == 0x1FU) {
    bits = sign | 0x7F800000U | (mantissa << 13U);
  } else {
    exponent += static_cast<uint32_t>(127 - 15);
    bits = sign | (exponent << 23U) | (mantissa << 13U);
  }
  float value = 0.0F;
  std::memcpy(&value, &bits, sizeof(value));
  return value;
}

bool ValidateOutput(ValidationContext &context, uint32_t index,
                    const std::array<float, 4> &expected, float *red) {
  void *mapped = nullptr;
  Check(vkMapMemory(context.device, context.buffers[index].memory, 0,
                    kOutputBytes, 0, &mapped),
        "vkMapMemory_failed");
  const auto *values = static_cast<const uint16_t *>(mapped);
  bool valid = true;
  constexpr float tolerance = 0.003F;
  for (uint32_t pixel = 0; pixel < kWidth * kHeight; ++pixel) {
    for (uint32_t component = 0; component < expected.size(); ++component) {
      const float actual = HalfToFloat(values[pixel * 4 + component]);
      if (!std::isfinite(actual) ||
          std::fabs(actual - expected[component]) > tolerance) {
        valid = false;
      }
      if (pixel == 0 && component == 0) {
        *red = actual;
      }
    }
  }
  vkUnmapMemory(context.device, context.buffers[index].memory);
  return valid;
}

uint64_t TimestampDelta(uint64_t start, uint64_t end, uint32_t valid_bits) {
  if (valid_bits >= 64) {
    return end - start;
  }
  const uint64_t mask = (1ULL << valid_bits) - 1ULL;
  return (end - start) & mask;
}

void SubmitAndValidate(ValidationContext &context, ValidationReport &report) {
  VkSubmitInfo submit_info{};
  submit_info.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
  submit_info.commandBufferCount = 1;
  submit_info.pCommandBuffers = &context.command_buffer;
  Check(vkQueueSubmit(context.queue, 1, &submit_info, context.fence),
        "vkQueueSubmit_failed");
  const VkResult wait_result = vkWaitForFences(
      context.device, 1, &context.fence, VK_TRUE, kFenceTimeoutNanoseconds);
  if (wait_result == VK_TIMEOUT) {
    context.abandon_resources = true;
    report.resources_quarantined = true;
    throw std::runtime_error("offscreen_fence_timeout");
  }
  Check(wait_result, "vkWaitForFences_failed");

  std::array<uint64_t, 4> timestamps{};
  Check(vkGetQueryPoolResults(
            context.device, context.query_pool, 0,
            static_cast<uint32_t>(timestamps.size()), sizeof(timestamps),
            timestamps.data(), sizeof(uint64_t),
            VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WAIT_BIT),
        "vkGetQueryPoolResults_failed");
  const uint64_t phase_13_ticks = TimestampDelta(timestamps[0], timestamps[1],
                                                 context.timestamp_valid_bits);
  const uint64_t phase_23_ticks = TimestampDelta(timestamps[2], timestamps[3],
                                                 context.timestamp_valid_bits);
  report.phase_13_gpu_ns = static_cast<uint64_t>(
      std::llround(phase_13_ticks * context.timestamp_period));
  report.phase_23_gpu_ns = static_cast<uint64_t>(
      std::llround(phase_23_ticks * context.timestamp_period));
  if (report.phase_13_gpu_ns == 0 || report.phase_23_gpu_ns == 0) {
    throw std::runtime_error("offscreen_timestamp_delta_zero");
  }

  report.phase_13_valid =
      ValidateOutput(context, 0, {1.0F / 3.0F, 1.0F / 6.0F, 1.0F / 12.0F, 1.0F},
                     &report.phase_13_red);
  report.phase_23_valid =
      ValidateOutput(context, 1, {2.0F / 3.0F, 1.0F / 3.0F, 1.0F / 6.0F, 1.0F},
                     &report.phase_23_red);
  report.shader_executed = true;
  if (!report.phase_13_valid || !report.phase_23_valid) {
    throw std::runtime_error("offscreen_phase_output_mismatch");
  }
  report.complete = true;
}

} // namespace

std::string RunVulkanOffscreenValidation() {
  ValidationContext context;
  ValidationReport report;
  try {
    CreateInstance(context);
    SelectPhysicalDevice(context, report);
    CreateDevice(context);
    for (auto &image : context.images) {
      CreateImage(context, image);
    }
    for (auto &buffer : context.buffers) {
      CreateBuffer(context, buffer);
    }
    CreatePipeline(context);
    CreateDescriptors(context);
    CreateCommandsAndQueries(context);
    RecordCommands(context);
    SubmitAndValidate(context, report);
  } catch (const std::exception &error) {
    report.error = error.what();
  }
  return BuildJson(report);
}

std::string ValidateVulkanOffscreen() {
  static const std::string validation = RunVulkanOffscreenValidation();
  return validation;
}

} // namespace rekazumi
