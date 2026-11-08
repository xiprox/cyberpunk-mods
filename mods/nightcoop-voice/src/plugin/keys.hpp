// The mute and radio keys, read from the OS keyboard so they work in combat, in menus and while loading.
#pragma once

#include "engine.hpp"

#include <atomic>
#include <string>
#include <thread>

namespace nv
{
// A game key name ("IK_F9", "IK_Mouse5") to a Windows key code, or 0 if it has none.
int VirtualKeyFromInputKey(const std::string& aName);

class KeyWatcher
{
public:
    explicit KeyWatcher(Engine& aEngine);
    ~KeyWatcher();

    void SetKeys(int aMuteKey, int aRadioKey);

    // While CET's overlay is open, typing in it mustn't reach the mic.
    void SetBlocked(bool aBlocked);

private:
    void Loop();

    Engine& m_engine;
    std::atomic<int> m_muteKey{0};
    std::atomic<int> m_radioKey{0};
    std::atomic<bool> m_blocked{false};
    std::atomic<bool> m_stop{false};
    std::thread m_thread;
};
} // namespace nv
