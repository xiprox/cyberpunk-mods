// The headset's key: a tap and a hold mean different things. Polled, so nothing is hooked; only while the game has focus.
#pragma once

#include <atomic>
#include <string>
#include <thread>

namespace hs
{
int VirtualKeyFromInputKey(const std::string& aName);

class KeyWatcher
{
public:
    using Callback = void (*)();

    KeyWatcher(Callback aTap, Callback aHoldStart, Callback aHoldEnd);
    ~KeyWatcher();

    void SetKey(int aKey);
    void SetBlocked(bool aBlocked); // while CET's overlay has the keyboard

private:
    void Loop();

    Callback m_tap;
    Callback m_holdStart;
    Callback m_holdEnd;
    std::atomic<int> m_key{0};
    std::atomic<bool> m_blocked{false};
    std::atomic<bool> m_stop{false};
    std::thread m_thread;
};
} // namespace hs
