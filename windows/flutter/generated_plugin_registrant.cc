//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <disk_space_2/disk_space_2_plugin.h>
#include <fvp/fvp_plugin_c_api.h>
#include <media_kit_libs_windows_video/media_kit_libs_windows_video_plugin_c_api.h>
#include <media_kit_video/media_kit_video_plugin_c_api.h>
#include <screen_retriever_windows/screen_retriever_windows_plugin_c_api.h>
#include <window_manager/window_manager_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  DiskSpace_2PluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("DiskSpace_2Plugin"));
  FvpPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FvpPluginCApi"));
  MediaKitLibsWindowsVideoPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("MediaKitLibsWindowsVideoPluginCApi"));
  MediaKitVideoPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("MediaKitVideoPluginCApi"));
  ScreenRetrieverWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ScreenRetrieverWindowsPluginCApi"));
  WindowManagerPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("WindowManagerPlugin"));
}
