#include "core/settings.hpp"

#include "core/common.hpp"

#include <cstdlib>
#include <fstream>

namespace nv
{
void Settings::Load(const std::filesystem::path& aPath)
{
    std::lock_guard lock(m_mutex);
    m_path = aPath;
    m_values.clear();

    std::ifstream file(aPath);
    std::string line;
    while (std::getline(file, line))
    {
        if (!line.empty() && line.back() == '\r')
        {
            line.pop_back();
        }
        const size_t split = line.find('=');
        if (split != std::string::npos && split > 0)
        {
            m_values[line.substr(0, split)] = line.substr(split + 1);
        }
    }
}

std::string Settings::Get(const std::string& aKey, const std::string& aDefault) const
{
    std::lock_guard lock(m_mutex);
    const auto found = m_values.find(aKey);
    return found == m_values.end() ? aDefault : found->second;
}

float Settings::GetFloat(const std::string& aKey, float aDefault) const
{
    const std::string text = Get(aKey);
    if (text.empty())
    {
        return aDefault;
    }
    char* end = nullptr;
    const float value = std::strtof(text.c_str(), &end);
    return end == text.c_str() ? aDefault : value;
}

bool Settings::GetBool(const std::string& aKey, bool aDefault) const
{
    const std::string text = Get(aKey);
    if (text.empty())
    {
        return aDefault;
    }
    return text == "1" || text == "true";
}

void Settings::Set(const std::string& aKey, const std::string& aValue)
{
    // A line break in a value would split the entry into two lines of the file.
    if (aKey.find_first_of("\r\n=") != std::string::npos || aValue.find_first_of("\r\n") != std::string::npos)
    {
        return;
    }
    std::lock_guard lock(m_mutex);
    const auto found = m_values.find(aKey);
    if (found != m_values.end() && found->second == aValue)
    {
        return;
    }
    m_values[aKey] = aValue;
    Save();
}

void Settings::Save() const
{
    if (m_path.empty())
    {
        return;
    }
    std::error_code error;
    std::filesystem::create_directories(m_path.parent_path(), error);

    // Written beside the real file and moved over it, so a crash can't leave half a settings file.
    std::filesystem::path temp = m_path;
    temp += L".tmp";
    {
        std::ofstream file(temp, std::ios::trunc);
        for (const auto& [key, value] : m_values)
        {
            file << key << '=' << value << '\n';
        }
        if (!file)
        {
            Logf(LogWarn, "settings: could not write the file");
            return;
        }
    }
    std::filesystem::rename(temp, m_path, error);
    if (error)
    {
        Logf(LogWarn, "settings: could not replace the file: %s", error.message().c_str());
    }
}
} // namespace nv
