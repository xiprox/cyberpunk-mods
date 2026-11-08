// The player's settings: a key=value text file next to the plugin. Safe from any thread.
#pragma once

#include <filesystem>
#include <map>
#include <mutex>
#include <string>

namespace nv
{
class Settings
{
public:
    void Load(const std::filesystem::path& aPath);

    std::string Get(const std::string& aKey, const std::string& aDefault = "") const;
    float GetFloat(const std::string& aKey, float aDefault) const;
    bool GetBool(const std::string& aKey, bool aDefault) const;

    // Writes the file when the value changed.
    void Set(const std::string& aKey, const std::string& aValue);

private:
    void Save() const;

    mutable std::mutex m_mutex;
    std::filesystem::path m_path;
    std::map<std::string, std::string> m_values;
};
} // namespace nv
