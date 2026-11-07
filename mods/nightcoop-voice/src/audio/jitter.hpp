// Holds a talker's packets just long enough to play them evenly. It waits briefly when a talker starts, plays one frame
// each 20 ms, and asks for repair when a packet is late or lost. The wait follows how uneven the arrivals have been.
#pragma once

#include <windows.h>

#include <array>
#include <cstdint>

namespace nv
{
struct JitterFrame
{
    enum Kind
    {
        None,   // nothing to play
        Packet, // decode data
        Repair, // the packet is lost: rebuild it from the redundancy in data, the next packet
        Conceal // lost with nothing to rebuild from: the decoder makes something up
    };

    Kind kind = None;
    uint8_t flags = 0;
    bool startOfSpurt = false; // reset the decoder first
    int size = 0;
    uint8_t data[512]{};
};

class JitterBuffer
{
public:
    JitterBuffer();
    ~JitterBuffer() = default;

    JitterBuffer(const JitterBuffer&) = delete;
    JitterBuffer& operator=(const JitterBuffer&) = delete;

    // From the network thread.
    void Push(uint16_t aSequence, uint8_t aFlags, const uint8_t* aData, int aSize, double aNowMs);

    // From the mixer, once per 20 ms frame.
    void Pull(double aNowMs, JitterFrame& aOut);

    int TargetFrames() const;

private:
    enum class State
    {
        Idle,
        Buffering,
        Playing
    };

    struct Slot
    {
        bool used = false;
        uint16_t sequence = 0;
        uint8_t flags = 0;
        int size = 0;
        uint8_t data[512]{};
    };

    static constexpr int kSlots = 128;
    static constexpr int kMaxConceal = 4; // 80 ms of guessing, then wait for the talker again

    Slot& SlotOf(uint16_t aSequence)
    {
        return m_slots[aSequence % kSlots];
    }
    bool Has(uint16_t aSequence)
    {
        const Slot& slot = SlotOf(aSequence);
        return slot.used && slot.sequence == aSequence;
    }
    int Queued();
    void TakeSlot(uint16_t aSequence, JitterFrame& aOut, JitterFrame::Kind aKind, bool aConsume);
    int WantedFrames() const;

    mutable SRWLOCK m_lock = SRWLOCK_INIT;
    std::array<Slot, kSlots> m_slots;
    State m_state = State::Idle;
    uint16_t m_next = 0;
    int m_conceals = 0;
    bool m_startPending = false;
    double m_bufferingSinceMs = 0.0;

    // Interarrival jitter as in RTP (RFC 3550), in ms.
    bool m_haveTransit = false;
    uint16_t m_lastSequence = 0;
    double m_lastArrivalMs = 0.0;
    double m_jitterMs = 0.0;
    int m_extraFrames = 0;      // grows on each underrun
    double m_lastUnderrunMs = 0.0;
};
} // namespace nv
