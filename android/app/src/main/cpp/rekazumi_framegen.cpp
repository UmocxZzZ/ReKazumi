#include <jni.h>
#include <vulkan/vulkan.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <sstream>
#include <string>
#include <vector>

#include "rekazumi_offscreen.h"

namespace {

constexpr char kProbeMarker[] = "ReKazumi framegen capability probe v1";

struct DeviceProbe {
  bool found = false;
  std::string name;
  uint32_t api_version = 0;
  bool external_memory_ahb = false;
  bool timeline_extension = false;
  bool timeline_feature = false;
};

std::string EscapeJson(const char* value) {
  std::ostringstream output;
  for (const unsigned char character : std::string(value)) {
    switch (character) {
      case '\\':
        output << "\\\\";
        break;
      case '"':
        output << "\\\"";
        break;
      case '\b':
        output << "\\b";
        break;
      case '\f':
        output << "\\f";
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
          output << character;
        }
    }
  }
  return output.str();
}

bool HasExtension(const std::vector<VkExtensionProperties>& extensions,
                  const char* name) {
  return std::any_of(
      extensions.begin(), extensions.end(),
      [name](const VkExtensionProperties& extension) {
        return std::strcmp(extension.extensionName, name) == 0;
      });
}

std::vector<VkExtensionProperties> EnumerateDeviceExtensions(
    VkPhysicalDevice device) {
  uint32_t count = 0;
  if (vkEnumerateDeviceExtensionProperties(device, nullptr, &count, nullptr) !=
          VK_SUCCESS ||
      count == 0) {
    return {};
  }

  std::vector<VkExtensionProperties> extensions(count);
  const VkResult result = vkEnumerateDeviceExtensionProperties(
      device, nullptr, &count, extensions.data());
  if (result != VK_SUCCESS && result != VK_INCOMPLETE) {
    return {};
  }
  extensions.resize(count);
  return extensions;
}

DeviceProbe ProbeDevice(
    VkPhysicalDevice device,
    PFN_vkGetPhysicalDeviceFeatures2 get_physical_device_features2) {
  DeviceProbe probe;
  probe.found = true;

  VkPhysicalDeviceProperties properties{};
  vkGetPhysicalDeviceProperties(device, &properties);
  probe.name = properties.deviceName;
  probe.api_version = properties.apiVersion;

  const auto extensions = EnumerateDeviceExtensions(device);
  probe.external_memory_ahb = HasExtension(
      extensions,
      VK_ANDROID_EXTERNAL_MEMORY_ANDROID_HARDWARE_BUFFER_EXTENSION_NAME);
  probe.timeline_extension =
      HasExtension(extensions, VK_KHR_TIMELINE_SEMAPHORE_EXTENSION_NAME);

  if (get_physical_device_features2 != nullptr &&
      properties.apiVersion >= VK_API_VERSION_1_1) {
    VkPhysicalDeviceTimelineSemaphoreFeatures timeline_features{};
    timeline_features.sType =
        VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES;
    VkPhysicalDeviceFeatures2 features{};
    features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
    features.pNext = &timeline_features;
    get_physical_device_features2(device, &features);
    probe.timeline_feature = timeline_features.timelineSemaphore == VK_TRUE;
  }

  return probe;
}

int DeviceScore(const DeviceProbe& probe) {
  return (probe.external_memory_ahb ? 2 : 0) +
         (probe.timeline_feature ? 1 : 0);
}

std::string BuildJson(const DeviceProbe& device, uint32_t loader_api_version,
                      const std::string& error) {
  const bool timeline_core = device.api_version >= VK_API_VERSION_1_2;
  const bool timeline_ready =
      device.timeline_feature && (timeline_core || device.timeline_extension);
  const bool prerequisites_ready =
      device.found && device.api_version >= VK_API_VERSION_1_1 &&
      device.external_memory_ahb && timeline_ready;

  std::ostringstream json;
  json << '{'
       << "\"probeMarker\":\"" << kProbeMarker << "\","
       << "\"probeComplete\":true,"
       << "\"hasPhysicalDevice\":" << (device.found ? "true" : "false")
       << ',' << "\"deviceName\":\"" << EscapeJson(device.name.c_str())
       << "\"," << "\"loaderApiVersion\":" << loader_api_version << ','
       << "\"deviceApiVersion\":" << device.api_version << ','
       << "\"deviceApiMajor\":" << VK_VERSION_MAJOR(device.api_version)
       << ',' << "\"deviceApiMinor\":" << VK_VERSION_MINOR(device.api_version)
       << ',' << "\"deviceApiPatch\":" << VK_VERSION_PATCH(device.api_version)
       << ',' << "\"hasExternalMemoryAhb\":"
       << (device.external_memory_ahb ? "true" : "false") << ','
       << "\"hasTimelineSemaphore\":" << (timeline_ready ? "true" : "false")
       << ',' << "\"nativePrerequisitesReady\":"
       << (prerequisites_ready ? "true" : "false") << ','
       << "\"transportBackendImplemented\":false,"
       << "\"error\":\"" << EscapeJson(error.c_str()) << "\"}";
  return json.str();
}

std::string ProbeVulkan() {
  uint32_t loader_api_version = VK_API_VERSION_1_0;
  const auto enumerate_instance_version =
      reinterpret_cast<PFN_vkEnumerateInstanceVersion>(
          vkGetInstanceProcAddr(VK_NULL_HANDLE, "vkEnumerateInstanceVersion"));
  if (enumerate_instance_version != nullptr) {
    const VkResult result = enumerate_instance_version(&loader_api_version);
    if (result != VK_SUCCESS) {
      return BuildJson({}, loader_api_version,
                       "vkEnumerateInstanceVersion_failed_" +
                           std::to_string(result));
    }
  }

  VkApplicationInfo application_info{};
  application_info.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
  application_info.pApplicationName = "ReKazumi";
  application_info.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
  application_info.pEngineName = "ReKazumi framegen probe";
  application_info.engineVersion = VK_MAKE_VERSION(1, 0, 0);
  application_info.apiVersion =
      std::min(loader_api_version, static_cast<uint32_t>(VK_API_VERSION_1_1));

  VkInstanceCreateInfo create_info{};
  create_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
  create_info.pApplicationInfo = &application_info;

  VkInstance instance = VK_NULL_HANDLE;
  const VkResult create_result = vkCreateInstance(&create_info, nullptr, &instance);
  if (create_result != VK_SUCCESS) {
    return BuildJson({}, loader_api_version,
                     "vkCreateInstance_failed_" +
                         std::to_string(create_result));
  }

  uint32_t device_count = 0;
  VkResult enumerate_result =
      vkEnumeratePhysicalDevices(instance, &device_count, nullptr);
  if (enumerate_result != VK_SUCCESS || device_count == 0) {
    vkDestroyInstance(instance, nullptr);
    return BuildJson({}, loader_api_version,
                     device_count == 0
                         ? "no_physical_device"
                         : "vkEnumeratePhysicalDevices_failed_" +
                               std::to_string(enumerate_result));
  }

  std::vector<VkPhysicalDevice> devices(device_count);
  enumerate_result =
      vkEnumeratePhysicalDevices(instance, &device_count, devices.data());
  if (enumerate_result != VK_SUCCESS && enumerate_result != VK_INCOMPLETE) {
    vkDestroyInstance(instance, nullptr);
    return BuildJson({}, loader_api_version,
                     "vkEnumeratePhysicalDevices_failed_" +
                         std::to_string(enumerate_result));
  }
  devices.resize(device_count);

  const auto get_physical_device_features2 =
      reinterpret_cast<PFN_vkGetPhysicalDeviceFeatures2>(
          vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceFeatures2"));

  DeviceProbe best_device;
  for (const VkPhysicalDevice device : devices) {
    const DeviceProbe candidate =
        ProbeDevice(device, get_physical_device_features2);
    if (!best_device.found || DeviceScore(candidate) > DeviceScore(best_device)) {
      best_device = candidate;
    }
  }

  vkDestroyInstance(instance, nullptr);
  return BuildJson(best_device, loader_api_version, "");
}

}  // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_predidit_rekazumi_MainActivity_probeNativeVulkanCapabilities(
    JNIEnv* environment, jobject /* activity */) {
  const std::string result = ProbeVulkan();
  return environment->NewStringUTF(result.c_str());
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_predidit_rekazumi_MainActivity_validateNativeVulkanOffscreen(
    JNIEnv* environment, jobject /* activity */) {
  const std::string result = rekazumi::ValidateVulkanOffscreen();
  return environment->NewStringUTF(result.c_str());
}
