@echo off
rem ASoftware iOS 26 GPU settings, for THIS window only (nothing is installed or saved).
rem 1) Only the Ryzen iGPU (DEV_164E) is visible to Vulkan apps; the RX 7700 XT is hidden.
rem 2) The Khronos Profiles layer (from Vulkan SDK 1.4.363.1, kept in this folder) hides
rem    VK_EXT_device_generated_commands, which makes AMD fail with Vulkan error -13.
rem    All its simulation features are switched off; it only removes that one extension.
set VK_LOADER_DEVICE_ID_FILTER=0x164E
set VK_ADD_LAYER_PATH=%~dp0
set VK_LOADER_LAYERS_ENABLE=VK_LAYER_KHRONOS_profiles
set VK_KHRONOS_PROFILES_PROFILE_EMULATION=false
set VK_KHRONOS_PROFILES_EMULATE_PORTABILITY=false
set VK_KHRONOS_PROFILES_EXCLUDE_DEVICE_EXTENSIONS=VK_EXT_device_generated_commands
echo iOS GPU settings on: iGPU only, device_generated_commands hidden.
