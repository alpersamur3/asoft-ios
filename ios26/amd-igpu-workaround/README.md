# AMD workaround: Vulkan failure -13 on iOS 26

On AMD GPUs, the iOS 26 first boot (step 17) and every later start fail with:

```
reims-vgpu: fatal: platform call MTLCreateSystemDefaultDevice(): the Vulkan runtime refused it: Vulkan failure -13
```

The AMD driver lists `VK_EXT_device_generated_commands`, but enabling it makes device creation fail. This folder hides that one extension from QEMU using the Khronos Profiles layer. It needs no rebuild, installs nothing, and changes no system settings: everything applies to one Command Prompt window only. metal2vulkan then runs those commands on the host instead.

Tested on a Ryzen 5 7600X iGPU (AMD Radeon(TM) Graphics, `DEV_164E`), Windows 11 10.0.26200, ASoftware iOS 0.2.0, iOS 26.6.2.

## Files

| File | What it is |
|---|---|
| `ios-gpu-env.cmd` | Sets the Vulkan loader and layer variables for the current window |
| `Start iOS 26 (AMD).bat` | Launcher: runs `ios-gpu-env.cmd`, then `Start-iOS26.cmd` |
| `VkLayer_khronos_profiles.dll` / `.json` | Khronos Profiles layer, unmodified, from the LunarG Vulkan SDK 1.4.363.1 (Windows) |
| `LICENSE-*.md/.txt` | Licenses for the layer (Apache-2.0) |

## Use

1. This folder ships at `ios26\amd-igpu-workaround` in the repo. Copy it anywhere, for example next to your ASoftware install.
2. **GPU filter:** `ios-gpu-env.cmd` sets `VK_LOADER_DEVICE_ID_FILTER=0x164E` (Ryzen 7000 iGPU). metal2vulkan prefers a discrete GPU, so this filter is what keeps iOS on the iGPU. Change it to your GPU's PCI device ID, which is shown in Device Manager > Display adapters > Properties > Details > Hardware Ids as `DEV_xxxx`. Delete the line to let it choose on its own. It needs Vulkan loader 1.4.326 or newer.
3. Edit the two paths at the top of `Start iOS 26 (AMD).bat`, then double-click it.
4. **Fresh install:** in `cmd` (not PowerShell 7), run `call <this folder>\ios-gpu-env.cmd` first, then `Install-ASoftware.cmd ...` in the same window. If step 17 already failed, the install resumes there.

Variables it sets:

```
VK_ADD_LAYER_PATH=<this folder>
VK_LOADER_LAYERS_ENABLE=VK_LAYER_KHRONOS_profiles
VK_KHRONOS_PROFILES_PROFILE_EMULATION=false
VK_KHRONOS_PROFILES_EMULATE_PORTABILITY=false
VK_KHRONOS_PROFILES_EXCLUDE_DEVICE_EXTENSIONS=VK_EXT_device_generated_commands
VK_LOADER_DEVICE_ID_FILTER=0x164E
```

Profile emulation and portability emulation are switched off, so the layer changes nothing except removing that one extension.

## Known on AMD
- **RX 7700 XT (dGPU, `0x747E`):** boots, but the screen is garbled (a cyan Apple logo with red junk pixels). Use the iGPU.
- **Shutting down:** after Shut down, the guest turns off but QEMU doesn't exit. Use Force quit.

## Proper fix
metal2vulkan already has `DeviceOptions::withhold_generated_commands`, but reims-vgpu's `platform.rs` `device_options()` never sets it. Setting it when DGC doesn't cover compute, or adding an env toggle, would make this folder unnecessary.

The Khronos Profiles layer is Copyright The Khronos Group Inc. and LunarG, Inc., licensed under Apache-2.0.
