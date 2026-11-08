#include "audio/jitter.hpp"

#include "core/common.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace nv
{
namespace
{
constexpr double kFrameMs = 20.0;
constexpr int kMinFrames = 2;        // 40 ms: the wait on a steady network
constexpr int kMaxFrames = 10;       // 200 ms: never wait longer than this
constexpr int kMaxExtraFrames = 4;
constexpr int kOverflowMargin = 5;   // this far past the wanted depth, drop a frame to catch up
constexpr double kExtraDecayMs = 15000.0;

// How far aLater is ahead of aEarlier, across the 16-bit wrap.
int SequenceAhead(uint16_t aLater, uint16_t aEarlier)
{
    return static_cast<int16_t>(static_cast<uint16_t>(aLater - aEarlier));
}

class ScopedLock
{
public:
    explicit ScopedLock(SRWLOCK& aLock)
        : m_lock(aLock)
    {
        AcquireSRWLockExclusive(&m_lock);
    }
    ~ScopedLock()
    {
        ReleaseSRWLockExclusive(&m_lock);
    }

private:
    SRWLOCK& m_lock;
};
} // namespace

JitterBuffer::JitterBuffer() = default;

int JitterBuffer::WantedFrames() const
{
    const int fromJitter = static_cast<int>(std::ceil(m_jitterMs * 2.5 / kFrameMs));
    return std::clamp(kMinFrames + fromJitter + m_extraFrames, kMinFrames, kMaxFrames);
}

int JitterBuffer::TargetFrames() const
{
    AcquireSRWLockExclusive(&m_lock);
    const int frames = WantedFrames();
    ReleaseSRWLockExclusive(&m_lock);
    return frames;
}

int JitterBuffer::Queued()
{
    int count = 0;
    for (const Slot& slot : m_slots)
    {
        if (slot.used && SequenceAhead(slot.sequence, m_next) >= 0)
        {
            ++count;
        }
    }
    return count;
}

void JitterBuffer::Push(uint16_t aSequence, uint8_t aFlags, const uint8_t* aData, int aSize, double aNowMs)
{
    if (aSize <= 0 || aSize > static_cast<int>(sizeof(Slot::data)))
    {
        return;
    }
    ScopedLock lock(m_lock);

    if (m_haveTransit && (aFlags & kFlagSpurt) == 0)
    {
        const int ahead = SequenceAhead(aSequence, m_lastSequence);
        if (ahead > 0)
        {
            const double expected = ahead * kFrameMs;
            const double difference = std::fabs((aNowMs - m_lastArrivalMs) - expected);
            m_jitterMs += (difference - m_jitterMs) / 16.0;
        }
    }
    const int aheadOfLast = SequenceAhead(aSequence, m_lastSequence);
    if (!m_haveTransit || aheadOfLast > 0)
    {
        m_haveTransit = true;
        m_lastSequence = aSequence;
        m_lastArrivalMs = aNowMs;
    }

    if (m_state == State::Idle)
    {
        // A talker mid-sentence caught us with nothing queued: that was an underrun, so hold a little more from now on.
        if ((aFlags & kFlagSpurt) == 0)
        {
            m_extraFrames = std::min(m_extraFrames + 1, kMaxExtraFrames);
            m_lastUnderrunMs = aNowMs;
        }
        m_state = State::Buffering;
        m_next = aSequence;
        m_bufferingSinceMs = aNowMs;
        m_startPending = true;
        m_conceals = 0;
    }
    else if (SequenceAhead(aSequence, m_next) < 0)
    {
        if (m_state == State::Buffering)
        {
            m_next = aSequence; // arrived out of order before playback began
        }
        else
        {
            return; // too late, its moment has passed
        }
    }
    else if (SequenceAhead(aSequence, m_next) >= kSlots)
    {
        return; // would overwrite frames still waiting
    }

    Slot& slot = SlotOf(aSequence);
    slot.used = true;
    slot.sequence = aSequence;
    slot.flags = aFlags;
    slot.size = aSize;
    std::memcpy(slot.data, aData, static_cast<size_t>(aSize));
}

void JitterBuffer::TakeSlot(uint16_t aSequence, JitterFrame& aOut, JitterFrame::Kind aKind, bool aConsume)
{
    Slot& slot = SlotOf(aSequence);
    aOut.kind = aKind;
    aOut.flags = slot.flags;
    aOut.size = slot.size;
    std::memcpy(aOut.data, slot.data, static_cast<size_t>(slot.size));
    if (aConsume)
    {
        slot.used = false;
    }
}

void JitterBuffer::Pull(double aNowMs, JitterFrame& aOut)
{
    ScopedLock lock(m_lock);
    aOut.kind = JitterFrame::None;
    aOut.startOfSpurt = false;
    aOut.size = 0;

    if (m_extraFrames > 0 && aNowMs - m_lastUnderrunMs > kExtraDecayMs)
    {
        --m_extraFrames;
        m_lastUnderrunMs = aNowMs;
    }

    if (m_state == State::Idle)
    {
        return;
    }

    const int wanted = WantedFrames();
    if (m_state == State::Buffering)
    {
        const bool deep = Queued() >= wanted;
        const bool waited = aNowMs - m_bufferingSinceMs >= wanted * kFrameMs;
        if (!deep && !waited)
        {
            return;
        }
        m_state = State::Playing;
    }

    aOut.startOfSpurt = m_startPending;
    m_startPending = false;

    // Fallen behind, after a hitch or a burst: skip ahead rather than stay late for the rest of the sentence.
    if (Queued() > wanted + kOverflowMargin)
    {
        SlotOf(m_next).used = false;
        ++m_next;
    }

    if (Has(m_next))
    {
        TakeSlot(m_next, aOut, JitterFrame::Packet, true);
        m_conceals = 0;
    }
    else if (m_conceals < kMaxConceal && Has(static_cast<uint16_t>(m_next + 1)))
    {
        TakeSlot(static_cast<uint16_t>(m_next + 1), aOut, JitterFrame::Repair, false);
        ++m_conceals;
    }
    else if (m_conceals < kMaxConceal && Queued() > 0)
    {
        aOut.kind = JitterFrame::Conceal;
        aOut.flags = SlotOf(static_cast<uint16_t>(m_next - 1)).flags;
        ++m_conceals;
    }
    else if (m_conceals < 2)
    {
        // Nothing queued: either the talker paused or the network is late. Bridge a moment in case it's the network.
        aOut.kind = JitterFrame::Conceal;
        aOut.flags = SlotOf(static_cast<uint16_t>(m_next - 1)).flags;
        ++m_conceals;
    }
    else
    {
        // Out of road. The talker stopped, or we underran; either way start over on the next packet.
        m_state = State::Idle;
        m_conceals = 0;
        m_haveTransit = false;
        for (Slot& slot : m_slots)
        {
            slot.used = false;
        }
        return;
    }
    ++m_next;
}
} // namespace nv
