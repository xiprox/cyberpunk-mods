// What travels over a link: a small clear header, then encrypted contents.
//
//   byte 0      packet type
//   byte 1      flags (kFlag*)
//   bytes 2-5   counter, never repeated by one sender under one key
//   bytes 6-9   sender's peer number
//   bytes 10-25 authentication tag
//   bytes 26-   ciphertext
//
// The whole group shares one key from the host, so the nonce is built from the sender and the counter.
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

namespace nv
{
constexpr size_t kPacketHeader = 26;
constexpr size_t kMaxPlain = 1000;
constexpr size_t kMaxPacket = kPacketHeader + kMaxPlain;

enum PacketType : uint8_t
{
    PacketAudio = 1,    // plain: u16 sequence, Opus frame
    PacketPresence = 2, // plain: see Presence in engine.cpp
};

using VoiceKey = std::array<uint8_t, 32>;

struct PacketInfo
{
    uint8_t type = 0;
    uint8_t flags = 0;
    uint32_t counter = 0;
    uint32_t sender = 0;
};

// Returns the packet's size. aOut holds at least kMaxPacket bytes; aSize is at most kMaxPlain.
size_t SealPacket(const VoiceKey& aKey, const PacketInfo& aInfo, const uint8_t* aPlain, size_t aSize, uint8_t* aOut);

// False when the packet is malformed or wasn't made with this key. aPlainOut holds at least kMaxPlain bytes.
bool OpenPacket(const VoiceKey& aKey, const uint8_t* aPacket, size_t aSize, PacketInfo& aInfo, uint8_t* aPlainOut,
                size_t& aPlainSize);

// Bytes from the system's secure random generator.
bool RandomBytes(void* aOut, size_t aSize);
} // namespace nv
