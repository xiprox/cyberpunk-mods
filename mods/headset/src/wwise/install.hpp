// Puts the effect on the game's buses once its Wwise is up and the headset is wanted, reads tuning.ini, and writes the log.
#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>

namespace hs
{
enum class InstallState
{
    Off,
    Waiting,      // for the game's Wwise to start
    NotAvailable, // this program doesn't export Wwise's functions, or its Wwise isn't the build this was made for
    Installed,
    Failed,
};

void StartInstaller(const std::filesystem::path& aTuningFile);
void StopInstaller();
InstallState GetInstallState();

// How many times aCode holds "mov dword ptr [rdx+4], aBuild", which is how the game's effects fill in PluginInfo::buildVersion.
int CountBuildStamps(const uint8_t* aCode, size_t aSize, uint32_t aBuild);

// Reads aFile now, if it changed; false when it didn't exist or hadn't changed.
bool ReadTuning(const std::filesystem::path& aFile);

// Writes aFile with every value commented out if it isn't there, first moving aside one an older version wrote with live values.
void PrepareTuningFile(const std::filesystem::path& aFile);
} // namespace hs
