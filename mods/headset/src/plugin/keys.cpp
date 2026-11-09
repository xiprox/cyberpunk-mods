#include "plugin/keys.hpp"

#include <windows.h>

#include <cstdlib>
#include <map>

namespace hs
{
namespace
{
constexpr DWORD kPollMs = 5;
constexpr ULONGLONG kHoldMs = 150; // a tap acts on release, because until then it might be a hold

bool GameHasFocus()
{
    DWORD process = 0;
    GetWindowThreadProcessId(GetForegroundWindow(), &process);
    return process == GetCurrentProcessId();
}
} // namespace

int VirtualKeyFromInputKey(const std::string& aName)
{
    if (aName.rfind("IK_", 0) != 0)
    {
        return 0;
    }
    const std::string key = aName.substr(3);
    if (key.size() == 1 && ((key[0] >= 'A' && key[0] <= 'Z') || (key[0] >= '0' && key[0] <= '9')))
    {
        return key[0];
    }
    if (key.size() >= 2 && key[0] == 'F' && key[1] >= '1' && key[1] <= '9')
    {
        const int number = std::atoi(key.c_str() + 1);
        if (number >= 1 && number <= 24)
        {
            return VK_F1 + number - 1;
        }
    }
    if (key.rfind("NumPad", 0) == 0 && key.size() == 7 && key[6] >= '0' && key[6] <= '9')
    {
        return VK_NUMPAD0 + (key[6] - '0');
    }

    static const std::map<std::string, int> kNamed{
        {"LeftMouse", VK_LBUTTON},     {"RightMouse", VK_RBUTTON},     {"MiddleMouse", VK_MBUTTON},
        {"Mouse4", VK_XBUTTON1},       {"Mouse5", VK_XBUTTON2},        {"Backspace", VK_BACK},
        {"Tab", VK_TAB},               {"Enter", VK_RETURN},           {"Pause", VK_PAUSE},
        {"CapsLock", VK_CAPITAL},      {"Escape", VK_ESCAPE},          {"Space", VK_SPACE},
        {"PageUp", VK_PRIOR},          {"PageDown", VK_NEXT},          {"End", VK_END},
        {"Home", VK_HOME},             {"Left", VK_LEFT},              {"Up", VK_UP},
        {"Right", VK_RIGHT},           {"Down", VK_DOWN},              {"Insert", VK_INSERT},
        {"Delete", VK_DELETE},         {"LShift", VK_LSHIFT},          {"RShift", VK_RSHIFT},
        {"LControl", VK_LCONTROL},     {"RControl", VK_RCONTROL},      {"LAlt", VK_LMENU},
        {"RAlt", VK_RMENU},            {"Alt", VK_MENU},               {"Shift", VK_SHIFT},
        {"Ctrl", VK_CONTROL},          {"NumStar", VK_MULTIPLY},       {"NumPlus", VK_ADD},
        {"NumMinus", VK_SUBTRACT},     {"NumPeriod", VK_DECIMAL},      {"NumSlash", VK_DIVIDE},
        {"Semicolon", VK_OEM_1},       {"Equals", VK_OEM_PLUS},        {"Comma", VK_OEM_COMMA},
        {"Minus", VK_OEM_MINUS},       {"Period", VK_OEM_PERIOD},      {"Slash", VK_OEM_2},
        {"Tilde", VK_OEM_3},           {"LeftBracket", VK_OEM_4},      {"Backslash", VK_OEM_5},
        {"RightBracket", VK_OEM_6},    {"SingleQuote", VK_OEM_7},
    };
    const auto found = kNamed.find(key);
    return found == kNamed.end() ? 0 : found->second;
}

KeyWatcher::KeyWatcher(Callback aTap, Callback aHoldStart, Callback aHoldEnd) : m_tap(aTap), m_holdStart(aHoldStart), m_holdEnd(aHoldEnd)
{
    m_thread = std::thread([this] { Loop(); });
}

KeyWatcher::~KeyWatcher()
{
    m_stop.store(true);
    if (m_thread.joinable())
    {
        m_thread.join();
    }
}

void KeyWatcher::SetKey(int aKey)
{
    m_key.store(aKey);
}

void KeyWatcher::SetBlocked(bool aBlocked)
{
    m_blocked.store(aBlocked);
}

void KeyWatcher::Loop()
{
    bool wasDown = false;
    bool holding = false;
    ULONGLONG pressedAt = 0;
    while (!m_stop.load())
    {
        Sleep(kPollMs);
        const int key = m_key.load();
        const bool down = key != 0 && !m_blocked.load() && GameHasFocus() && (GetAsyncKeyState(key) & 0x8000) != 0;
        if (down && !wasDown)
        {
            pressedAt = GetTickCount64();
            holding = false;
        }
        else if (down && !holding && GetTickCount64() - pressedAt >= kHoldMs)
        {
            holding = true;
            m_holdStart();
        }
        else if (!down && wasDown)
        {
            if (holding)
            {
                m_holdEnd();
            }
            else
            {
                m_tap();
            }
            holding = false;
        }
        wasDown = down;
    }
}
} // namespace hs
