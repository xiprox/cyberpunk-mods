#include "net/packet.hpp"

#include <windows.h>

#include <bcrypt.h>
#include <monocypher.h>

#include <cstring>

namespace nv
{
namespace
{
constexpr size_t kAdSize = 10;
constexpr size_t kTagOffset = 10;

void PutU32(uint8_t* aOut, uint32_t aValue)
{
    aOut[0] = static_cast<uint8_t>(aValue);
    aOut[1] = static_cast<uint8_t>(aValue >> 8);
    aOut[2] = static_cast<uint8_t>(aValue >> 16);
    aOut[3] = static_cast<uint8_t>(aValue >> 24);
}

uint32_t GetU32(const uint8_t* aIn)
{
    return static_cast<uint32_t>(aIn[0]) | static_cast<uint32_t>(aIn[1]) << 8 | static_cast<uint32_t>(aIn[2]) << 16 |
           static_cast<uint32_t>(aIn[3]) << 24;
}

void MakeNonce(const PacketInfo& aInfo, uint8_t aNonce[24])
{
    std::memset(aNonce, 0, 24);
    PutU32(aNonce, aInfo.sender);
    PutU32(aNonce + 4, aInfo.counter);
}
} // namespace

size_t SealPacket(const VoiceKey& aKey, const PacketInfo& aInfo, const uint8_t* aPlain, size_t aSize, uint8_t* aOut)
{
    aOut[0] = aInfo.type;
    aOut[1] = aInfo.flags;
    PutU32(aOut + 2, aInfo.counter);
    PutU32(aOut + 6, aInfo.sender);

    uint8_t nonce[24];
    MakeNonce(aInfo, nonce);
    crypto_aead_lock(aOut + kPacketHeader, aOut + kTagOffset, aKey.data(), nonce, aOut, kAdSize, aPlain, aSize);
    return kPacketHeader + aSize;
}

bool OpenPacket(const VoiceKey& aKey, const uint8_t* aPacket, size_t aSize, PacketInfo& aInfo, uint8_t* aPlainOut,
                size_t& aPlainSize)
{
    if (aSize < kPacketHeader || aSize > kMaxPacket)
    {
        return false;
    }
    aInfo.type = aPacket[0];
    aInfo.flags = aPacket[1];
    aInfo.counter = GetU32(aPacket + 2);
    aInfo.sender = GetU32(aPacket + 6);
    aPlainSize = aSize - kPacketHeader;

    uint8_t nonce[24];
    MakeNonce(aInfo, nonce);
    return crypto_aead_unlock(aPlainOut, aPacket + kTagOffset, aKey.data(), nonce, aPacket, kAdSize,
                              aPacket + kPacketHeader, aPlainSize) == 0;
}

bool RandomBytes(void* aOut, size_t aSize)
{
    return BCRYPT_SUCCESS(BCryptGenRandom(nullptr, static_cast<PUCHAR>(aOut), static_cast<ULONG>(aSize),
                                          BCRYPT_USE_SYSTEM_PREFERRED_RNG));
}
} // namespace nv
