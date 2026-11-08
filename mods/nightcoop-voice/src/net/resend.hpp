// When to send our mod list to NightCoop's players again. A player's list can fail to register on another machine
// (seen once: the host's, on a guest joining), and then those two never set up a link. NightCoop sends the list again
// whenever a mod registers or unregisters, so while anyone is stuck we do that, less and less often.
#pragma once

#include <algorithm>

namespace nv
{
class ResendSchedule
{
public:
    static constexpr double kFirstMs = 8000.0; // an ordinary link is up well before this
    static constexpr double kLongestMs = 60000.0;
    static constexpr int kMostResends = 12;

    // Call now and then; true means send the list now. aStuck: some player has no link, or we've no word of their mods.
    bool Update(double aNowMs, bool aStuck)
    {
        if (!aStuck)
        {
            m_active = false;
            m_sent = 0;
            return false;
        }
        if (!m_active)
        {
            m_active = true;
            m_delayMs = kFirstMs;
            m_nextMs = aNowMs + kFirstMs;
            return false;
        }
        if (aNowMs < m_nextMs || m_sent >= kMostResends)
        {
            return false;
        }
        ++m_sent;
        m_delayMs = std::min(m_delayMs * 2.0, kLongestMs);
        m_nextMs = aNowMs + m_delayMs;
        return true;
    }

    int Sent() const
    {
        return m_sent;
    }

private:
    bool m_active = false;
    int m_sent = 0;
    double m_delayMs = kFirstMs;
    double m_nextMs = 0.0;
};
} // namespace nv
