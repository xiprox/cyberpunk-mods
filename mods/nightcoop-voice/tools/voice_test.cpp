// Checks the mod without the game: effects by their measured output, packets, the jitter buffer, real hole-punched
// links between two engines on this PC, the Relay over a fake NightCoop channel, and the audio devices. Run it with no
// arguments; it exits non-zero on a failure.
// No microphone audio is stored or sent anywhere: the device check reports a level and throws the samples away.

#include "audio/acoustics.hpp"
#include "audio/automix.hpp"
#include "audio/car.hpp"
#include "audio/dsp.hpp"
#include "audio/headset_link.hpp"
#include "audio/jitter.hpp"
#include "audio/mic.hpp"
#include "audio/mixer.hpp"
#include "audio/spatial.hpp"
#include "audio/wasapi.hpp"
#include "engine.hpp"
#include "headset_api.h"
#include "net/link.hpp"
#include "net/packet.hpp"
#include "net/resend.hpp"

#include <opus.h>

#include <mmdeviceapi.h>

#include <audioclient.h>
#include <ksmedia.h>

#undef small // rpcndr.h, under the audio headers, defines it as char, and the room tests use the word

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <deque>
#include <filesystem>
#include <map>
#include <memory>
#include <random>
#include <string>
#include <thread>
#include <vector>

using namespace nv;

namespace
{
int g_failures = 0;

void Check(bool aOk, const char* aWhat, const char* aDetailFormat = "", double aDetail = 0.0)
{
    std::printf("  %s  %s", aOk ? "ok  " : "FAIL", aWhat);
    if (aDetailFormat[0])
    {
        std::printf("  (");
        std::printf(aDetailFormat, aDetail);
        std::printf(")");
    }
    std::printf("\n");
    if (!aOk)
    {
        ++g_failures;
    }
}

// A rough stand-in for speech: a pitched buzz with moving formants, broken into syllables.
// aFloor keeps the gaps between syllables from going fully silent, as a real room's would.
std::vector<float> FakeSpeech(int aSamples, float aFloor = 0.f)
{
    std::vector<float> out(static_cast<size_t>(aSamples));
    float phase = 0.f;
    for (int i = 0; i < aSamples; ++i)
    {
        const float t = static_cast<float>(i) / kRate;
        const float pitch = 120.f + 25.f * std::sin(2.f * kPi * 1.3f * t);
        phase += pitch / kRate;
        phase -= std::floor(phase);
        const float buzz = 2.f * phase - 1.f;
        const float formant1 = std::sin(2.f * kPi * (500.f + 200.f * std::sin(2.f * kPi * 2.1f * t)) * t);
        const float formant2 = std::sin(2.f * kPi * (1500.f + 500.f * std::sin(2.f * kPi * 1.7f * t)) * t);
        const float syllable = aFloor + (1.f - aFloor) * std::pow(std::max(0.f, std::sin(2.f * kPi * 3.5f * t)), 0.5f);
        out[static_cast<size_t>(i)] = 0.25f * syllable * (0.5f * buzz + 0.3f * formant1 * buzz + 0.2f * formant2 * buzz);
    }
    return out;
}

// How strong one frequency is in a signal.
float Goertzel(const std::vector<float>& aSignal, float aHz)
{
    const float w = 2.f * kPi * aHz / kRate;
    const float coefficient = 2.f * std::cos(w);
    float s1 = 0.f;
    float s2 = 0.f;
    for (const float sample : aSignal)
    {
        const float s0 = sample + coefficient * s1 - s2;
        s2 = s1;
        s1 = s0;
    }
    const float power = s1 * s1 + s2 * s2 - coefficient * s1 * s2;
    return std::sqrt(std::max(power, 0.f)) / static_cast<float>(aSignal.size());
}

float Rms(const std::vector<float>& aSignal)
{
    double sum = 0.0;
    for (const float sample : aSignal)
    {
        sum += static_cast<double>(sample) * sample;
    }
    return static_cast<float>(std::sqrt(sum / std::max<size_t>(aSignal.size(), 1)));
}

void TestPackets()
{
    std::printf("packets\n");
    VoiceKey key;
    RandomBytes(key.data(), key.size());
    const uint8_t message[] = "hello from the other side";
    PacketInfo info;
    info.type = PacketAudio;
    info.flags = kFlagRadio;
    info.counter = 77;
    info.sender = 4;
    uint8_t packet[kMaxPacket];
    const size_t size = SealPacket(key, info, message, sizeof(message), packet);

    PacketInfo opened;
    uint8_t plain[kMaxPlain];
    size_t plainSize = 0;
    Check(OpenPacket(key, packet, size, opened, plain, plainSize) && plainSize == sizeof(message) &&
              std::memcmp(plain, message, sizeof(message)) == 0 && opened.sender == 4 && opened.flags == kFlagRadio,
          "a sealed packet opens with the right contents");

    uint8_t tampered[kMaxPacket];
    std::memcpy(tampered, packet, size);
    tampered[kPacketHeader + 3] ^= 1;
    Check(!OpenPacket(key, tampered, size, opened, plain, plainSize), "a changed byte in the contents is refused");
    std::memcpy(tampered, packet, size);
    tampered[1] ^= kFlagRadio;
    Check(!OpenPacket(key, tampered, size, opened, plain, plainSize), "a changed flag in the header is refused");

    VoiceKey other = key;
    other[0] ^= 1;
    Check(!OpenPacket(other, packet, size, opened, plain, plainSize), "the wrong key is refused");
    Check(!OpenPacket(key, packet, 5, opened, plain, plainSize), "a packet shorter than the header is refused");
}

void TestSpatial()
{
    std::printf("proximity rules\n");
    SpatialInput input;
    input.listenerForward = {0.f, 1.f, 0.f};
    input.listenerRight = {1.f, 0.f, 0.f};

    input.talkerPosition = {0.f, 2.f, 0.f};
    SpatialOutput close = ComputeSpatial(input);
    Check(std::fabs(close.gainLeft - 1.f) < 0.01f && std::fabs(close.gainRight - 1.f) < 0.01f,
          "straight ahead within 2 m is full volume in both ears");

    const auto dbAt = [&](float aMeters) {
        input.talkerPosition = {0.f, aMeters, 0.f};
        return 20.f * std::log10(std::max(ComputeSpatial(input).gainLeft, 1e-6f));
    };
    std::printf("  distance: 5 m %.1f dB, 10 m %.1f dB, 15 m %.1f dB, 25 m %.1f dB, 35 m %.1f dB\n", dbAt(5.f), dbAt(10.f),
                dbAt(15.f), dbAt(25.f), dbAt(35.f));
    Check(dbAt(5.f) < -2.2f && dbAt(5.f) > -3.2f, "5 m is about 3 dB down", "%.1f dB", dbAt(5.f));
    Check(dbAt(10.f) < -5.4f && dbAt(10.f) > -6.4f, "10 m about 6", "%.1f dB", dbAt(10.f));
    Check(dbAt(15.f) < -8.2f && dbAt(15.f) > -9.2f, "15 m about 9", "%.1f dB", dbAt(15.f));
    Check(dbAt(15.f) > dbAt(40.f) * 0.5f, "which is less than halfway down to 40 m's level", "%.1f dB", dbAt(15.f));

    input.talkerPosition = {0.f, 21.5f, 0.f};
    const SpatialOutput middle = ComputeSpatial(input);
    Check(middle.gainLeft > 0.15f && middle.gainLeft < 0.35f, "a voice at 21.5 m is much quieter", "%.2f",
          middle.gainLeft);
    Check(middle.lowpassHz < close.lowpassHz * 0.7f, "distant voices audibly lose high end", "%.0f Hz", middle.lowpassHz);
    Check(middle.reverbSend / middle.gainLeft > close.reverbSend / close.gainLeft, "and have more room around them");

    Check(dbAt(35.f) < -17.9f && dbAt(35.f) > -18.9f, "at 35 m a voice hasn't begun to fade", "%.1f dB", dbAt(35.f));
    Check(dbAt(40.f) < -20.1f && dbAt(40.f) > -21.1f, "nor at 40 m", "%.1f dB", dbAt(40.f));
    Check(dbAt(45.f) < -28.3f && dbAt(45.f) > -29.3f, "halfway through the fade it's 6 dB further down", "%.1f dB", dbAt(45.f));
    input.talkerPosition = {0.f, 40.f, 0.f};
    const float dullest = ComputeSpatial(input).lowpassHz;
    input.talkerPosition = {0.f, 45.f, 0.f};
    Check(std::fabs(ComputeSpatial(input).lowpassHz - dullest) < 1.f, "past 40 m a voice gets no duller", "%.0f Hz", dullest);
    input.talkerPosition = {0.f, 50.f, 0.f};
    Check(!ComputeSpatial(input).audible, "at 50 m a voice is silent");
    input.talkerPosition = {0.f, 49.f, 0.f};
    Check(ComputeSpatial(input).gainLeft < 0.01f, "just inside 50 m a voice has nearly faded out");

    {
        // The radio mic: held or in combat, and a moment more.
        RadioMic mic;
        Check(!mic.SetHeld(true, 0.0) && !mic.On(), "outside a session the key does nothing");
        mic.SetHeld(false, 0.0);
        Check(!mic.SetCombat(true, 0.0) && !mic.On(), "and neither does combat");
        mic.SetCombat(false, 0.0);
        mic.SetSession(true, 0.0);
        Check(!mic.On() && !mic.OnAir(0.0), "in a session it starts off");
        Check(mic.SetHeld(true, 100.0) && mic.On() && mic.OnAir(100.0), "holding the key puts it on");
        Check(mic.SetHeld(false, 1000.0) && !mic.On(), "letting go takes it off");
        Check(mic.OnAir(1240.0) && !mic.OnAir(1260.0), "but what's said in the next 250 ms still goes on the radio");
        Check(mic.SetCombat(true, 2000.0) && mic.On() && mic.InCombat(), "combat puts it on without the key");
        Check(!mic.SetHeld(true, 2100.0) && !mic.SetHeld(false, 2200.0) && mic.On(), "and a press in combat leaves it on");
        Check(!mic.SetHeld(true, 2300.0) && !mic.SetCombat(false, 2400.0) && mic.On(), "held as combat ends, it stays on");
        Check(mic.SetHeld(false, 2500.0) && !mic.On(), "until the key comes up");
        mic.SetCombat(true, 3000.0);
        Check(mic.SetSession(false, 3100.0) && !mic.On(), "and leaving the session takes it off");
    }

    input.talkerPosition = {5.f, 0.f, 0.f};
    const SpatialOutput right = ComputeSpatial(input);
    Check(right.gainRight > right.gainLeft * 1.8f, "a talker on the right is louder in the right ear", "%.2f",
          right.gainRight / right.gainLeft);
    Check(right.delayLeft > 28.f && right.delayLeft < 34.f && right.delayRight == 0.f,
          "and reaches the left ear about 0.65 ms later", "%.1f samples", right.delayLeft);
    Check(right.shadowLeftHz < 2500.f && right.shadowRightHz >= SpatialOutput::kNoShadowHz,
          "and the head blocks treble from the left ear", "%.0f Hz", right.shadowLeftHz);
    input.talkerPosition = {-5.f, 0.f, 0.f};
    const SpatialOutput left = ComputeSpatial(input);
    Check(left.gainLeft > left.gainRight * 1.8f && left.delayRight > 28.f && left.delayLeft == 0.f,
          "a talker on the left mirrors all of that");

    input.talkerPosition = {0.f, 5.f, 0.f};
    const SpatialOutput ahead = ComputeSpatial(input);
    input.talkerPosition = {0.f, -5.f, 0.f};
    const SpatialOutput behindYou = ComputeSpatial(input);
    Check(behindYou.lowpassHz < ahead.lowpassHz * 0.5f && behindYou.gainLeft < ahead.gainLeft,
          "a voice behind you sounds different from one ahead", "%.0f Hz", behindYou.lowpassHz);
    Check(ahead.delayLeft == 0.f && ahead.delayRight == 0.f && behindYou.delayLeft == 0.f, "and both reach your ears together");

    input.talkerPosition = {0.f, 5.f, 4.f};
    const SpatialOutput above = ComputeSpatial(input);
    Check(std::fabs(above.gainLeft - above.gainRight) < 0.01f, "a voice above and ahead stays centered");

    input.talkerPosition = {5.f, 0.f, 0.f};
    input.headphones = false;
    const SpatialOutput speakers = ComputeSpatial(input);
    Check(speakers.delayLeft == 0.f && speakers.shadowLeftHz >= SpatialOutput::kNoShadowHz && speakers.gainRight > speakers.gainLeft,
          "with Headphones off it's a plain pan");
    input.headphones = true;

    input.talkerPosition = {0.f, 10.f, 0.f};
    input.occlusion = 0.f;
    const SpatialOutput clear = ComputeSpatial(input);
    input.occlusion = 1.f;
    const SpatialOutput walled = ComputeSpatial(input);
    Check(walled.gainLeft < clear.gainLeft * 0.5f && walled.lowpassHz < 1000.f,
          "a wall makes a voice quieter and muffled", "%.0f Hz", walled.lowpassHz);

    const auto through = [&](float aOcclusion) {
        input.talkerPosition = {0.f, 2.f, 0.f};
        input.occlusion = aOcclusion;
        return ComputeSpatial(input);
    };
    const SpatialOutput door = through(0.55f);
    const SpatialOutput thinWall = through(0.6f);
    const SpatialOutput thickWall = through(1.f);
    const SpatialOutput edge = through(0.12f);
    const auto lossDb = [](const SpatialOutput& aOutput) { return -20.f * std::log10(aOutput.gainLeft); };
    std::printf("  through: door %.1f dB, %.0f Hz; thin wall %.1f dB, %.0f Hz; thick wall %.1f dB, %.0f Hz; one ray of five %.1f dB, %.0f Hz\n",
                lossDb(door), door.lowpassHz, lossDb(thinWall), thinWall.lowpassHz, lossDb(thickWall), thickWall.lowpassHz,
                lossDb(edge), edge.lowpassHz);
    Check(lossDb(door) > 8.f && lossDb(door) < 12.f && door.lowpassHz < 2000.f, "a closed door is clearly muffled");
    Check(lossDb(thinWall) > lossDb(door) && lossDb(thickWall) > lossDb(thinWall) + 5.f, "and thicker walls more so");
    Check(lossDb(edge) < 3.f && edge.lowpassHz > 5000.f, "while just clipping a door frame stays gentle");
    input.occlusion = 0.f;

    input.occlusion = 1.f;
    input.sharedCabin = 1.f;
    input.talkerPosition = {0.5f, 1.f, 0.f};
    const SpatialOutput shared = ComputeSpatial(input);
    Check(shared.lowpassHz >= 15000.f && shared.reverbSend == 0.f && std::max(shared.gainLeft, shared.gainRight) > 0.9f,
          "riders in one vehicle hear each other clean, whatever the rays hit");

    input.occlusion = 0.f;
    input.sharedCabin = 0.f;
    input.separatedCabin = 1.f;
    input.talkerPosition = {0.f, 2.f, 0.f};
    const SpatialOutput cabinClose = ComputeSpatial(input);
    Check(cabinClose.audible && cabinClose.lowpassHz <= 1000.f && cabinClose.lowpassHz > 700.f && cabinClose.gainLeft < 0.46f,
          "through a car's cabin close by is muffled to a murmur, its vowels left and its words gone", "%.2f", cabinClose.gainLeft);
    const auto cabinGain = [&](float aMeters) {
        input.talkerPosition = {0.f, aMeters, 0.f};
        input.separatedCabin = 0.f;
        const float open = ComputeSpatial(input).gainLeft;
        input.separatedCabin = 1.f;
        return ComputeSpatial(input).gainLeft / open;
    };
    Check(std::fabs(cabinGain(1.f) - 0.45f) < 0.01f && std::fabs(cabinGain(3.f) - 0.45f) < 0.01f,
          "it takes the same 7 dB at the door as at 3 m", "%.2f at 3 m", cabinGain(3.f));
    Check(std::fabs(cabinGain(4.f) - 0.225f) < 0.01f, "then fades out", "%.2f at 4 m", cabinGain(4.f));
    input.talkerPosition = {0.f, 5.5f, 0.f};
    Check(!ComputeSpatial(input).audible, "through a car's cabin past 5 m is silent");
}

std::vector<std::vector<uint8_t>> EncodeFrames(const std::vector<float>& aPcm)
{
    int error = 0;
    OpusEncoder* encoder = opus_encoder_create(kRate, 1, OPUS_APPLICATION_VOIP, &error);
    opus_encoder_ctl(encoder, OPUS_SET_BITRATE(32000));
    std::vector<std::vector<uint8_t>> frames;
    for (size_t at = 0; at + kFrame <= aPcm.size(); at += kFrame)
    {
        uint8_t packet[480];
        const int size = opus_encode_float(encoder, aPcm.data() + at, kFrame, packet, sizeof(packet));
        frames.emplace_back(packet, packet + size);
    }
    opus_encoder_destroy(encoder);
    return frames;
}

void TestJitter()
{
    std::printf("jitter buffer\n");
    const std::vector<uint8_t> payload(40, 0x55);
    JitterFrame frame;

    {
        JitterBuffer jitter;
        int played = 0;
        for (int i = 0; i < 50; ++i)
        {
            const double now = i * 20.0;
            jitter.Push(static_cast<uint16_t>(i), i == 0 ? kFlagSpurt : 0, payload.data(), 40, now);
            jitter.Pull(now + 1.0, frame);
            played += frame.kind == JitterFrame::Packet ? 1 : 0;
        }
        // All but the two frames still waiting in the buffer.
        Check(played >= 47, "steady arrivals play every packet", "%.0f of 50", played);
    }
    {
        JitterBuffer jitter;
        double now = 0.0;
        jitter.Push(100, kFlagSpurt, payload.data(), 40, now);
        jitter.Push(101, 0, payload.data(), 40, now + 20.0);
        jitter.Pull(now + 200.0, frame);
        Check(frame.kind == JitterFrame::Packet && frame.startOfSpurt, "the first frame says to reset the decoder");
        jitter.Pull(now + 220.0, frame);
        Check(frame.kind == JitterFrame::Packet && !frame.startOfSpurt, "later frames don't");
    }
    {
        JitterBuffer jitter;
        double now = 0.0;
        jitter.Push(10, kFlagSpurt, payload.data(), 40, now);
        jitter.Push(12, 0, payload.data(), 40, now + 40.0); // 11 is lost
        jitter.Push(13, 0, payload.data(), 40, now + 60.0);
        jitter.Pull(now + 80.0, frame);
        jitter.Pull(now + 100.0, frame);
        Check(frame.kind == JitterFrame::Repair, "a lost packet is rebuilt from the one after it");
        jitter.Pull(now + 120.0, frame);
        Check(frame.kind == JitterFrame::Packet, "and play goes on");
    }
    {
        JitterBuffer jitter;
        double now = 0.0;
        jitter.Push(5, kFlagSpurt, payload.data(), 40, now);
        jitter.Push(7, 0, payload.data(), 40, now + 1.0);
        jitter.Push(6, 0, payload.data(), 40, now + 2.0); // out of order
        int played = 0;
        for (int i = 0; i < 3; ++i)
        {
            jitter.Pull(now + 100.0 + i * 20.0, frame);
            played += frame.kind == JitterFrame::Packet ? 1 : 0;
        }
        Check(played == 3, "packets out of order still play in order");
    }
    {
        JitterBuffer jitter;
        double now = 0.0;
        jitter.Push(0, kFlagSpurt, payload.data(), 40, now);
        jitter.Pull(now + 100.0, frame);
        int conceals = 0;
        for (int i = 0; i < 10; ++i)
        {
            jitter.Pull(now + 120.0 + i * 20.0, frame);
            conceals += frame.kind == JitterFrame::Conceal ? 1 : 0;
        }
        Check(conceals > 0 && conceals <= 2 && frame.kind == JitterFrame::None,
              "when a talker stops it bridges briefly, then goes quiet", "%.0f conceals", conceals);
    }
    {
        JitterBuffer jitter;
        std::mt19937 random(7);
        std::uniform_real_distribution<double> spread(0.0, 60.0);
        double arrival = 0.0;
        for (uint16_t i = 0; i < 200; ++i)
        {
            arrival = i * 20.0 + spread(random);
            jitter.Push(i, i == 0 ? kFlagSpurt : 0, payload.data(), 40, arrival);
            if (i % 2 == 0)
            {
                jitter.Pull(arrival, frame);
                jitter.Pull(arrival, frame);
            }
        }
        Check(jitter.TargetFrames() > 2, "a rough network makes it hold more", "%.0f frames", jitter.TargetFrames());
    }
}

void TestMic()
{
    std::printf("mic chain\n");
    int packets = 0;
    int spurts = 0;
    int bytes = 0;
    MicProcessor mic([&](const uint8_t*, int aSize, bool aSpurt) {
        ++packets;
        spurts += aSpurt ? 1 : 0;
        bytes += aSize;
    });

    const std::vector<float> silence(kRate * 2, 0.f);
    mic.Process(silence.data(), static_cast<int>(silence.size()));
    Check(packets == 0, "digital silence sends nothing");

    std::mt19937 random(3);
    std::normal_distribution<float> noise(0.f, 0.01f);
    std::vector<float> hiss(kRate * 2);
    for (float& sample : hiss)
    {
        sample = noise(random);
    }
    mic.Process(hiss.data(), static_cast<int>(hiss.size()));
    const int hissPackets = packets;
    Check(hissPackets < 30, "steady fan-like noise barely opens the gate", "%.0f packets in 2 s", hissPackets);

    mic.SetGateThreshold(0.f); // the fake speech isn't real speech, so let the level alone open the gate
    packets = spurts = bytes = 0;
    const std::vector<float> speech = FakeSpeech(kRate * 2);
    mic.Process(speech.data(), static_cast<int>(speech.size()));
    Check(packets >= 80, "sound through an open gate is sent", "%.0f packets in 2 s", packets);
    Check(spurts >= 1, "the first packet is marked as the start");
    if (packets > 0)
    {
        const double kbps = bytes * 8.0 / 2.0 / 1000.0;
        Check(kbps > 5.0 && kbps < 50.0, "the bitrate stays reasonable", "%.1f kbit/s", kbps);
    }
    Check(mic.Level() > 0.1f, "the level meter moves", "%.2f", mic.Level());

    mic.SetMuted(true);
    mic.Process(silence.data(), kRate / 2); // let the open frame finish
    packets = 0;
    mic.Process(speech.data(), static_cast<int>(speech.size()));
    Check(packets == 0, "muted sends nothing, whatever you say");
    mic.SetMuted(false);
}

void TestListenerAndFacing()
{
    std::printf("facing, underwater, slow motion\n");
    SpatialInput input;
    input.listenerForward = {0.f, 1.f, 0.f};
    input.listenerRight = {1.f, 0.f, 0.f};
    input.talkerPosition = {0.f, 6.f, 0.f};
    const SpatialOutput unknown = ComputeSpatial(input);

    // The talker stands ahead of the listener, so facing -y is facing them.
    input.talkerForward = {0.f, -1.f, 0.f};
    const SpatialOutput facing = ComputeSpatial(input);
    Check(std::fabs(facing.gainLeft - unknown.gainLeft) < 0.001f && std::fabs(facing.lowpassHz - unknown.lowpassHz) < 1.f,
          "a talker facing you sounds the same as one whose direction isn't known");

    input.talkerForward = {1.f, 0.f, 0.f};
    const SpatialOutput sideways = ComputeSpatial(input);
    input.talkerForward = {0.f, 1.f, 0.f};
    const SpatialOutput turned = ComputeSpatial(input);
    const float turnedDb = 20.f * std::log10(turned.gainLeft / facing.gainLeft);
    Check(turnedDb < -2.5f && turnedDb > -6.f, "a talker with their back turned is a little quieter", "%.1f dB", turnedDb);
    Check(turned.lowpassHz < facing.lowpassHz * 0.4f, "and much duller", "%.0f Hz", turned.lowpassHz);
    Check(sideways.lowpassHz < facing.lowpassHz && sideways.lowpassHz > turned.lowpassHz,
          "side on sits between the two", "%.0f Hz", sideways.lowpassHz);
    Check(turned.reverbSend > 0.f && std::fabs(turned.reverbSend - facing.reverbSend) < 0.001f,
          "turning away leaves what the room gives back");
    Check(turned.audible == facing.audible, "and it doesn't change whether they send");

    input.sharedCabin = 1.f;
    const SpatialOutput sameCar = ComputeSpatial(input);
    Check(sameCar.turnedAway == 0.f, "in the same vehicle it doesn't matter");
    input.sharedCabin = 0.f;

    input.talkerPosition = {0.f, 0.2f, 0.f};
    Check(ComputeSpatial(input).turnedAway < 0.3f, "nor right beside someone", "%.2f", ComputeSpatial(input).turnedAway);
    input.talkerPosition = {6.f, 0.f, 0.f};
    input.talkerForward = {};
    const SpatialOutput dry = ComputeSpatial(input);

    input.underwater = 1.f;
    const SpatialOutput wet = ComputeSpatial(input);
    const float wetDb = 20.f * std::log10(std::max(wet.gainLeft, wet.gainRight) / std::max(dry.gainLeft, dry.gainRight));
    Check(wetDb < -15.f, "underwater, voices nearly die", "%.1f dB", wetDb);
    Check(wet.lowpassHz <= 350.f, "and lose everything but the low end", "%.0f Hz", wet.lowpassHz);
    Check(wet.reverbSend == 0.f, "with no room around them");
    Check(wet.gainRight / wet.gainLeft < dry.gainRight / dry.gainLeft * 0.8f, "and it's hard to tell where they are", "%.2f",
          wet.gainRight / wet.gainLeft);
    input.talkerPosition = {0.f, 38.5f, 0.f};
    const bool reachedDry = [&] {
        SpatialInput above = input;
        above.underwater = 0.f;
        return ComputeSpatial(above).audible;
    }();
    Check(ComputeSpatial(input).audible == reachedDry, "diving doesn't stop you sending to someone at the edge of hearing");
    input.underwater = 0.f;
    input.talkerPosition = {0.f, 6.f, 0.f};

    Check(SlowMotionFromWorldSpeed(1.f) == 0.f, "the world at full speed isn't slow motion");
    Check(SlowMotionFromWorldSpeed(0.3f) == 1.f, "0.3, as logged in play, is fully slow", "%.2f", SlowMotionFromWorldSpeed(0.3f));
    Check(SlowMotionFromWorldSpeed(0.02f) == 1.f, "and so is NightCoop's nearly stopped 0.02");
    Check(SlowMotionFromWorldSpeed(0.f) == 0.f, "a load or a stopped world, which reads 0, isn't");
    const float halfway = SlowMotionFromWorldSpeed(0.625f);
    Check(halfway > 0.4f && halfway < 0.6f, "easing out of it eases the effect", "%.2f", halfway);

    const SpatialOutput normal = ComputeSpatial(input);
    input.slowMotion = 1.f;
    const SpatialOutput slowed = ComputeSpatial(input);
    Check(slowed.lowpassHz < normal.lowpassHz * 0.3f, "slow motion makes voices dull", "%.0f Hz", slowed.lowpassHz);
    Check(slowed.reverbSend > normal.reverbSend * 2.f, "and roomy", "%.1f times the room", slowed.reverbSend / normal.reverbSend);
    Check(slowed.audible == normal.audible, "without changing whether anyone sends");
}

void TestEasing()
{
    std::printf("muffling takes time to change\n");
    constexpr double kStepMs = 33.0;

    // Until the value gets within a hair of its target, in milliseconds, updating as often as the game does.
    const auto timeTo = [](auto&& aUpdate, auto&& aValue, float aTarget) {
        double now = 100000.0;
        for (int i = 0; i < 600; ++i)
        {
            now += kStepMs;
            aUpdate(now);
            if (std::fabs(aValue() - aTarget) < 0.01f)
            {
                return static_cast<float>(i + 1) * static_cast<float>(kStepMs);
            }
        }
        return 1e9f;
    };

    TalkerEase talker;
    talker.Update(CabinSeparated, 0.f, 100000.0);
    Check(talker.SeparatedCabin() == 1.f, "the first update goes straight there, since nobody heard the change");
    const float carOut = timeTo([&](double aNow) { talker.Update(CabinNone, 0.f, aNow); }, [&] { return talker.SeparatedCabin(); }, 0.f);
    Check(carOut > 800.f && carOut < 1100.f, "getting out of a car takes about a second", "%.0f ms", carOut);

    // Halfway out: between the two sounds, not one or the other.
    SpatialInput input;
    input.listenerForward = {0.f, 1.f, 0.f};
    input.listenerRight = {1.f, 0.f, 0.f};
    input.talkerPosition = {0.f, 3.f, 0.f};
    const SpatialOutput outside = ComputeSpatial(input);
    input.separatedCabin = 1.f;
    const SpatialOutput inside = ComputeSpatial(input);
    input.separatedCabin = 0.5f;
    const SpatialOutput halfway = ComputeSpatial(input);
    Check(halfway.gainLeft > inside.gainLeft && halfway.gainLeft < outside.gainLeft, "halfway out, the level is in between", "%.2f", halfway.gainLeft);
    Check(halfway.lowpassHz > inside.lowpassHz * 1.5f && halfway.lowpassHz < outside.lowpassHz * 0.7f, "and so is the treble", "%.0f Hz", halfway.lowpassHz);

    input.separatedCabin = 0.f;
    input.sharedCabin = 0.5f;
    input.occlusion = 1.f;
    const SpatialOutput climbing = ComputeSpatial(input);
    input.sharedCabin = 0.f;
    const SpatialOutput walled = ComputeSpatial(input);
    Check(climbing.lowpassHz > walled.lowpassHz, "getting into the same car clears up gradually too", "%.0f Hz", climbing.lowpassHz);
    input.occlusion = 0.f;

    TalkerEase walls;
    walls.Update(CabinNone, 0.f, 100000.0);
    const float wallIn = timeTo([&](double aNow) { walls.Update(CabinNone, 1.f, aNow); }, [&] { return walls.Occlusion(); }, 1.f);
    Check(wallIn > 400.f && wallIn < 600.f, "a thick wall comes in over half a second", "%.0f ms", wallIn);

    // The rays only report five times a second. What's heard must not move in steps that size.
    TalkerEase steps;
    steps.Update(CabinNone, 0.f, 100000.0);
    float biggestJump = 0.f;
    double now = 100000.0;
    float previous = 0.f;
    for (int i = 0; i < 60; ++i)
    {
        now += kStepMs;
        const float reported = i < 6 ? 0.4f : i < 12 ? 0.64f : 0.78f;
        steps.Update(CabinNone, reported, now);
        biggestJump = std::max(biggestJump, std::fabs(steps.Occlusion() - previous));
        previous = steps.Occlusion();
    }
    Check(biggestJump < 0.08f, "the rays' steps are heard as a slope", "%.3f at most per update", biggestJump);

    TalkerEase gap;
    gap.Update(CabinSeparated, 0.f, 100000.0);
    gap.Update(CabinNone, 0.f, 103000.0);
    Check(gap.SeparatedCabin() == 0.f, "after a load it goes straight there too");

    ListenerEase listener;
    listener.Update(false, 0.f, 100000.0);
    const float slowIn = timeTo([&](double aNow) { listener.Update(false, 1.f, aNow); }, [&] { return listener.SlowMotion(); }, 1.f);
    Check(slowIn > 150.f && slowIn < 300.f, "slow motion hits fast", "%.0f ms", slowIn);
    const float slowOut = timeTo([&](double aNow) { listener.Update(false, 0.f, aNow); }, [&] { return listener.SlowMotion(); }, 0.f);
    Check(slowOut > 650.f && slowOut < 900.f, "and fades over most of a second, even when the world snaps back", "%.0f ms", slowOut);
    const float waterIn = timeTo([&](double aNow) { listener.Update(true, 0.f, aNow); }, [&] { return listener.Underwater(); }, 1.f);
    Check(waterIn > 180.f && waterIn < 330.f, "going under takes a quarter of a second", "%.0f ms", waterIn);
    const float waterOut = timeTo([&](double aNow) { listener.Update(false, 0.f, aNow); }, [&] { return listener.Underwater(); }, 0.f);
    Check(waterOut > 300.f && waterOut < 480.f, "coming up a bit longer", "%.0f ms", waterOut);

    // The radio through a half-faded dive, with the same blend the nearby path uses at its ends.
    input.underwater = 0.5f;
    const SpatialOutput halfWet = ComputeSpatial(input);
    input.underwater = 1.f;
    const SpatialOutput wet = ComputeSpatial(input);
    input.underwater = 0.f;
    Check(halfWet.gainLeft > wet.gainLeft && halfWet.gainLeft < outside.gainLeft && halfWet.lowpassHz > wet.lowpassHz,
          "half under sits between the air and the water", "%.0f Hz", halfWet.lowpassHz);
}

void TestRadio()
{
    std::printf("radio\n");
    const auto tone = [](float aHz, float aLevel) {
        std::vector<float> out(kRate);
        for (int i = 0; i < kRate; ++i)
        {
            out[static_cast<size_t>(i)] = aLevel * std::sin(2.f * kPi * aHz * static_cast<float>(i) / kRate);
        }
        return out;
    };
    struct Ears
    {
        std::vector<float> on;
    };
    // The first tenth of a second is left out, while the filters and the encoding settle.
    const auto run = [](const std::vector<float>& aInput) {
        RadioEffect radio;
        Ears ears;
        for (size_t i = 0; i < aInput.size(); ++i)
        {
            const float on = radio.Process(aInput[i], 1.f);
            if (i >= kRate / 10)
            {
                ears.on.push_back(on);
            }
        }
        return ears;
    };

    const float level = std::pow(10.f, kNominalSpeechDb / 20.f);
    const Ears mid = run(tone(1000.f, level));
    const float toneRms = Goertzel(mid.on, 1000.f) * std::sqrt(2.f);
    const float total = Rms(mid.on);
    const float gritDb = 10.f * std::log10(toneRms * toneRms / std::max(total * total - toneRms * toneRms, 1e-9f));
    Check(gritDb > 9.f && gritDb < 22.f, "the encoding adds grit without burying the voice", "tone %.1f dB over the rest", gritDb);

    const float bass = Goertzel(run(tone(150.f, level)).on, 150.f);
    Check(bass < 0.25f * Goertzel(mid.on, 1000.f), "the earpiece has no bass", "%.2f of the mids", bass / Goertzel(mid.on, 1000.f));

    const float peak = Goertzel(run(tone(2500.f, level)).on, 2500.f);
    Check(peak > 1.1f * Goertzel(mid.on, 1000.f), "and rings around 2.5 kHz", "%.2f times the mids", peak / Goertzel(mid.on, 1000.f));

    const Ears silent = run(std::vector<float>(kRate, 0.f));
    Check(Rms(silent.on) < 0.0005f, "no hiss between words", "rms %.6f", Rms(silent.on));

    RadioEffect radio;
    radio.KeyUp();
    std::vector<float> click;
    while (click.size() < kRate / 10)
    {
        click.push_back(radio.Process(0.f, 0.f));
    }
    float clickPeak = 0.f;
    size_t lastHeard = 0;
    for (size_t i = 0; i < click.size(); ++i)
    {
        clickPeak = std::max(clickPeak, std::fabs(click[i]));
        if (std::fabs(click[i]) > 0.003f)
        {
            lastHeard = i;
        }
    }
    Check(clickPeak > 0.05f && clickPeak < 0.6f, "keying up gives a click, even before the voice fades in", "peak %.2f", clickPeak);
    Check(lastHeard < kRate * 15 / 1000, "and it's short", "%.1f ms", static_cast<float>(lastHeard) * 1000.f / kRate);
}

// Runs packets through a voice in the mixer and returns what comes out of each ear.
struct Rendered
{
    std::vector<float> left;
    std::vector<float> right;
};

Rendered RenderThrough(Mixer& aMixer, PeerId aPeer, const std::vector<std::vector<uint8_t>>& aFrames, uint8_t aFlags)
{
    Rendered out;
    float block[kBlock * 2];
    uint16_t sequence = 0;
    // Paced like real time, since the jitter buffer goes by the clock.
    for (const auto& frame : aFrames)
    {
        aMixer.PushPacket(aPeer, sequence, static_cast<uint8_t>(aFlags | (sequence == 0 ? kFlagSpurt : 0)), frame.data(),
                          static_cast<int>(frame.size()));
        ++sequence;
        for (int b = 0; b < 2; ++b)
        {
            aMixer.Render(block);
            for (int i = 0; i < kBlock; ++i)
            {
                out.left.push_back(block[i * 2]);
                out.right.push_back(block[i * 2 + 1]);
            }
        }
        const double until = NowMs() + 19.5;
        while (NowMs() < until)
        {
            Sleep(1);
        }
    }
    return out;
}

void TestMixer()
{
    std::printf("mixer (runs in real time)\n");
    // Two tones: one the radio's band keeps, one it cuts.
    std::vector<float> tones(kRate);
    for (int i = 0; i < kRate; ++i)
    {
        const float t = static_cast<float>(i) / kRate;
        tones[static_cast<size_t>(i)] = 0.2f * std::sin(2.f * kPi * 1000.f * t) + 0.2f * std::sin(2.f * kPi * 6000.f * t);
    }
    const auto frames = EncodeFrames(tones);

    {
        Mixer mixer;
        mixer.AddVoice(1);
        SpatialInput input;
        input.listenerForward = {0.f, 1.f, 0.f};
        input.listenerRight = {1.f, 0.f, 0.f};
        input.talkerPosition = {0.f, 1.f, 0.f};
        const SpatialOutput spatial = ComputeSpatial(input);
        std::vector<float> left;
        // Positions have to stay fresh or proximity fades out.
        mixer.SetSpatial(1, spatial);
        const Rendered clean = RenderThrough(mixer, 1, frames, 0);
        const float keep = Goertzel(clean.left, 1000.f);
        const float high = Goertzel(clean.left, 6000.f);
        Check(keep > 0.01f && high > 0.3f * keep, "a nearby voice keeps its high end", "%.2f high/mid", high / keep);
    }
    {
        // A talker on the right, heard through the whole chain: what each ear really gets.
        Mixer mixer;
        mixer.AddVoice(1);
        SpatialInput input;
        input.listenerForward = {0.f, 1.f, 0.f};
        input.listenerRight = {1.f, 0.f, 0.f};
        input.talkerPosition = {1.5f, 0.f, 0.f};
        mixer.SetSpatial(1, ComputeSpatial(input));
        const Rendered side = RenderThrough(mixer, 1, frames, 0);
        const float nearHigh = Goertzel(side.right, 6000.f);
        const float farHigh = Goertzel(side.left, 6000.f);
        Check(nearHigh > farHigh * 4.f, "the far ear gets much less treble", "%.1f times less", nearHigh / farHigh);
        Check(Rms(side.right) > Rms(side.left) * 1.2f, "and less level overall", "%.2f times less",
              Rms(side.right) / Rms(side.left));

        // Find the delay by sliding one ear against the other at a frequency the head doesn't block.
        Biquad leftLow;
        Biquad rightLow;
        leftLow.SetLowpass(1200.f);
        rightLow.SetLowpass(1200.f);
        std::vector<float> leftBand;
        std::vector<float> rightBand;
        for (size_t i = side.left.size() / 2; i < side.left.size(); ++i)
        {
            leftBand.push_back(leftLow.Process(side.left[i]));
            rightBand.push_back(rightLow.Process(side.right[i]));
        }
        // What's left under 1.2 kHz is the 1 kHz tone, which repeats every 48 samples, so lags a period apart score
        // almost alike: searching both sides sometimes picked 35 - 48 = -13. The far ear can only be later, and by less
        // than a period, so only that range is searched.
        int bestLag = 0;
        double bestScore = -1e9;
        for (int lag = 0; lag < 48; ++lag)
        {
            double score = 0.0;
            for (size_t i = 48; i + 48 < leftBand.size(); ++i)
            {
                score += static_cast<double>(leftBand[i + lag]) * rightBand[i];
            }
            if (score > bestScore)
            {
                bestScore = score;
                bestLag = lag;
            }
        }
        Check(bestLag >= 28 && bestLag <= 35, "and hears it about 0.65 ms later", "%.0f samples", bestLag);
    }
    {
        Mixer plain;
        plain.AddVoice(1);
        const float plainMid = Goertzel(RenderThrough(plain, 1, frames, kFlagRadio).left, 1000.f);

        Mixer close;
        close.AddVoice(1);
        close.SetSpatial(1, SpatialOutput{});
        const float closeMid = Goertzel(RenderThrough(close, 1, frames, kFlagRadio).left, 1000.f);
        Check(closeMid > plainMid * 0.9f, "a partner with a fresh position plays on the radio as fully as one with none",
              "%.2f of normal", closeMid / plainMid);
    }
    {
        Mixer mixer;
        mixer.AddVoice(1);
        const Rendered radio = RenderThrough(mixer, 1, frames, kFlagRadio);
        const float mid = Goertzel(radio.left, 1000.f);
        const float high = Goertzel(radio.left, 6000.f);
        Check(mid > 0.01f, "the radio plays with no position at all", "%.3f", mid);
        Check(high < 0.1f * mid, "the radio cuts the high end", "%.3f high/mid", high / mid);
        Check(Rms(radio.left) > 0.f && std::fabs(Rms(radio.left) - Rms(radio.right)) < 0.001f,
              "the radio plays in both ears alike, as in the headset");
    }
    {
        // What the listener's own state does to the earpiece, using a tone in its peak so it has treble to lose.
        std::vector<float> bright(kRate);
        for (int i = 0; i < kRate; ++i)
        {
            bright[static_cast<size_t>(i)] = 0.1f * std::sin(2.f * kPi * 2500.f * static_cast<float>(i) / kRate);
        }
        const auto brightFrames = EncodeFrames(bright);

        Mixer plain;
        plain.AddVoice(1);
        const float plainHigh = Goertzel(RenderThrough(plain, 1, brightFrames, kFlagRadio).left, 2500.f);

        Mixer diving;
        diving.AddVoice(1);
        diving.SetListenerEffects(1.f, 0.f);
        const float divingHigh = Goertzel(RenderThrough(diving, 1, brightFrames, kFlagRadio).left, 2500.f);
        Check(divingHigh < plainHigh * 0.25f && divingHigh > 0.f, "underwater, the radio goes dull but stays there", "%.2f of normal",
              divingHigh / plainHigh);

        Mixer slowed;
        slowed.AddVoice(1);
        slowed.SetListenerEffects(0.f, 1.f);
        const float slowedHigh = Goertzel(RenderThrough(slowed, 1, brightFrames, kFlagRadio).left, 2500.f);
        Check(slowedHigh < plainHigh * 0.7f && slowedHigh > divingHigh, "in slow motion it dulls less than that", "%.2f of normal",
              slowedHigh / plainHigh);
    }
    {
        Mixer mixer;
        mixer.AddVoice(1);
        const Rendered silent = RenderThrough(mixer, 1, frames, 0);
        Check(Rms(silent.left) < 0.001f, "a nearby voice with no position stays silent", "%.5f", Rms(silent.left));
    }
    {
        Mixer mixer;
        mixer.AddVoice(1);
        mixer.SetPeerMuted(1, true);
        const Rendered muted = RenderThrough(mixer, 1, frames, kFlagRadio);
        Check(Rms(muted.left) < 0.001f, "muting a player silences their radio too");
    }
    {
        Mixer mixer;
        mixer.AddVoice(1);
        mixer.SetMasterGain(0.25f);
        const Rendered lowered = RenderThrough(mixer, 1, frames, kFlagRadio);
        Mixer full;
        full.AddVoice(1);
        const Rendered normal = RenderThrough(full, 1, frames, kFlagRadio);
        const float ratio = Rms(lowered.left) / Rms(normal.left);
        Check(ratio > 0.2f && ratio < 0.32f, "the master gain turns all voices down together", "%.2f of normal", ratio);
    }
    {
        // After the mic chain's level, so this compares them as they'd really arrive.
        std::vector<float> speech = FakeSpeech(kRate);
        const float scale = std::pow(10.f, kNominalSpeechDb / 20.f) / Rms(speech);
        for (float& sample : speech)
        {
            sample *= scale;
        }
        const auto speechFrames = EncodeFrames(speech);

        Mixer nearby;
        nearby.AddVoice(1);
        SpatialInput input;
        input.listenerForward = {0.f, 1.f, 0.f};
        input.listenerRight = {1.f, 0.f, 0.f};
        input.talkerPosition = {0.f, 1.f, 0.f};
        nearby.SetSpatial(1, ComputeSpatial(input));
        const float nearDb = 20.f * std::log10(Rms(RenderThrough(nearby, 1, speechFrames, 0).left));

        Mixer both;
        both.AddVoice(1);
        const float bothDb = 20.f * std::log10(Rms(RenderThrough(both, 1, speechFrames, kFlagRadio).left));
        Check(std::fabs(bothDb - nearDb) < 1.5f, "in both ears the radio matches a nearby voice", "radio %+.1f dB",
              bothDb - nearDb);
    }
    {
        Mixer mixer;
        mixer.SetTestRoute(TestRoute::Radio);
        mixer.AddVoice(kSelfVoice);
        const Rendered test = RenderThrough(mixer, kSelfVoice, frames, kFlagRadio);
        Check(Rms(test.left) > 0.01f, "hear-yourself plays through the radio path");
    }
}

// ---- rooms, corners and echoes, in a made-up world of boxes

struct Box
{
    Vec3 low;
    Vec3 high;
    float thinWall = 0.f;
    float soft = 0.f;
};

struct FakeWorld
{
    std::vector<Box> walls;
    std::vector<Box> doors;
    int rays = 0;
    bool normals = true;

    // A hollow box with walls this thick, its floor at z = aLow.z.
    void AddHollow(const Vec3& aLow, const Vec3& aHigh, float aThick = 0.3f)
    {
        walls.push_back({{aLow.x - aThick, aLow.y - aThick, aLow.z - aThick}, {aHigh.x + aThick, aHigh.y + aThick, aLow.z}});
        walls.push_back({{aLow.x - aThick, aLow.y - aThick, aHigh.z}, {aHigh.x + aThick, aHigh.y + aThick, aHigh.z + aThick}});
        walls.push_back({{aLow.x - aThick, aLow.y - aThick, aLow.z}, {aLow.x, aHigh.y + aThick, aHigh.z}});
        walls.push_back({{aHigh.x, aLow.y - aThick, aLow.z}, {aHigh.x + aThick, aHigh.y + aThick, aHigh.z}});
        walls.push_back({{aLow.x, aLow.y - aThick, aLow.z}, {aHigh.x, aLow.y, aHigh.z}});
        walls.push_back({{aLow.x, aHigh.y, aLow.z}, {aHigh.x, aHigh.y + aThick, aHigh.z}});
    }

    static bool Hits(const Box& aBox, const Vec3& aFrom, const Vec3& aTo, float& aAt, Vec3& aNormal)
    {
        float enter = 0.f;
        float leave = 1.f;
        Vec3 normal;
        const float from[3] = {aFrom.x, aFrom.y, aFrom.z};
        const float to[3] = {aTo.x, aTo.y, aTo.z};
        const float low[3] = {aBox.low.x, aBox.low.y, aBox.low.z};
        const float high[3] = {aBox.high.x, aBox.high.y, aBox.high.z};
        for (int axis = 0; axis < 3; ++axis)
        {
            const float along = to[axis] - from[axis];
            if (std::fabs(along) < 1e-6f)
            {
                if (from[axis] < low[axis] || from[axis] > high[axis])
                {
                    return false;
                }
                continue;
            }
            float t1 = (low[axis] - from[axis]) / along;
            float t2 = (high[axis] - from[axis]) / along;
            const float side = t1 < t2 ? -1.f : 1.f;
            if (t1 > t2)
            {
                std::swap(t1, t2);
            }
            if (t1 > enter)
            {
                enter = t1;
                normal = {axis == 0 ? side : 0.f, axis == 1 ? side : 0.f, axis == 2 ? side : 0.f};
            }
            leave = std::min(leave, t2);
            if (enter > leave)
            {
                return false;
            }
        }
        aAt = enter;
        aNormal = normal;
        return true;
    }

    RayAnswer Cast(const RayRequest& aRay)
    {
        ++rays;
        RayAnswer answer;
        float nearest = 2.f;
        Vec3 normal;
        const auto at = [&](float aT) {
            return Vec3{aRay.from.x + (aRay.to.x - aRay.from.x) * aT, aRay.from.y + (aRay.to.y - aRay.from.y) * aT,
                        aRay.from.z + (aRay.to.z - aRay.from.z) * aT};
        };
        if (aRay.groups != RayGroups::DoorsOnly)
        {
            for (const Box& wall : walls)
            {
                float t = 0.f;
                if (Hits(wall, aRay.from, aRay.to, t, normal) && t < nearest)
                {
                    nearest = t;
                    answer.result = RayResult::Wall;
                    answer.position = at(t);
                    answer.normal = normals ? normal : Vec3{};
                    answer.thinWall = wall.thinWall;
                    answer.soft = wall.soft;
                }
            }
            if (answer.result == RayResult::Wall)
            {
                return answer;
            }
        }
        if (aRay.groups != RayGroups::Walls)
        {
            ++rays; // the game casts a second ray for doors
            for (const Box& door : doors)
            {
                float t = 0.f;
                if (Hits(door, aRay.from, aRay.to, t, normal) && t < nearest)
                {
                    nearest = t;
                    answer.result = RayResult::ClosedDoor;
                    answer.position = at(t);
                }
            }
        }
        return answer;
    }
};

// Stands a listener and a talker in a world for a while, one game frame at a time, with the plugin's limit on rays.
struct Scene
{
    FakeWorld world;
    Acoustics acoustics;
    Vec3 listener;
    Vec3 talker;
    int cabin = CabinNone;
    bool talking = true;
    double now = 100000.0;

    void Run(float aSeconds, float aFps = 30.f)
    {
        const double step = 1000.0 / aFps;
        for (double elapsed = 0.0; elapsed < aSeconds * 1000.0; elapsed += step)
        {
            acoustics.SetListener(listener, now);
            acoustics.SetTalker(1, talker, cabin, false, talking, now);
            RayRequest ray;
            for (int i = 0; i < 12 && acoustics.NextRay(ray, now); ++i)
            {
                acoustics.ReportRay(world.Cast(ray));
            }
            now += step;
        }
    }

    // Walks a player along a line, as if on foot, so that they leave a trail.
    void Walk(Vec3& aWho, const Vec3& aTo, float aSpeed = 4.f)
    {
        const Vec3 from = aWho;
        const float dx = aTo.x - from.x;
        const float dy = aTo.y - from.y;
        const float dz = aTo.z - from.z;
        const float length = std::sqrt(dx * dx + dy * dy + dz * dz);
        const int steps = std::max(static_cast<int>(length / aSpeed * 30.f), 1);
        for (int i = 1; i <= steps; ++i)
        {
            const float share = static_cast<float>(i) / static_cast<float>(steps);
            aWho = {from.x + dx * share, from.y + dy * share, from.z + dz * share};
            Run(1.f / 30.f);
        }
    }
};

RoomSound RoomOf(Scene& aScene)
{
    aScene.listener = aScene.listener;
    aScene.Run(1.f);
    return aScene.acoustics.Room();
}

void TestRooms()
{
    std::printf("rooms measured by rays\n");
    const auto measure = [](const char* aName, auto&& aBuild, const Vec3& aStand) {
        Scene scene;
        aBuild(scene.world);
        scene.listener = aStand;
        scene.talker = {aStand.x + 1.f, aStand.y, aStand.z};
        const RoomSound room = RoomOf(scene);
        std::printf("  %s: closed %.2f, %.1f m, rings %.2f s\n", aName, room.enclosure, room.meters, room.decaySeconds);
        return room;
    };

    const RoomSound closet = measure("closet", [](FakeWorld& aWorld) { aWorld.AddHollow({0.f, 0.f, 0.f}, {1.5f, 1.5f, 2.4f}); }, {0.75f, 0.75f, 1.6f});
    const RoomSound room = measure("room", [](FakeWorld& aWorld) { aWorld.AddHollow({0.f, 0.f, 0.f}, {5.f, 5.f, 3.f}); }, {2.5f, 2.5f, 1.6f});
    const RoomSound hall = measure("hall", [](FakeWorld& aWorld) { aWorld.AddHollow({0.f, 0.f, 0.f}, {40.f, 30.f, 12.f}); }, {20.f, 15.f, 1.6f});
    const RoomSound tunnel = measure("tunnel", [](FakeWorld& aWorld) { aWorld.AddHollow({-400.f, 0.f, 0.f}, {400.f, 8.f, 5.f}); }, {0.f, 4.f, 1.6f});
    const RoomSound street = measure("street", [](FakeWorld& aWorld) {
        aWorld.walls.push_back({{-400.f, -400.f, -1.f}, {400.f, 400.f, 0.f}});
        aWorld.walls.push_back({{-400.f, 0.f, 0.f}, {400.f, -1.f, 60.f}});
        aWorld.walls.push_back({{-400.f, 16.f, 0.f}, {400.f, 17.f, 60.f}});
    }, {0.f, 8.f, 1.6f});
    const RoomSound plaza = measure("plaza", [](FakeWorld& aWorld) { aWorld.walls.push_back({{-400.f, -400.f, -1.f}, {400.f, 400.f, 0.f}}); }, {0.f, 0.f, 1.6f});
    // A long balcony, as on the real one that sounded like a tunnel: wall on one side, a ceiling over it, and across a
    // courtyard another building, close enough for the rays to hit.
    const auto buildBalcony = [](FakeWorld& aWorld) {
        aWorld.walls.push_back({{-400.f, -400.f, -1.f}, {400.f, 400.f, 0.f}});
        aWorld.walls.push_back({{-30.f, -1.f, 3.f}, {30.f, 4.f, 4.f}});       // the ceiling, as deep as the walkway
        aWorld.walls.push_back({{-30.f, -2.f, 0.f}, {30.f, 0.f, 60.f}});      // the wall behind it
        aWorld.walls.push_back({{-31.f, -2.f, 0.f}, {-30.f, 4.f, 3.f}});      // the far ends of the walkway
        aWorld.walls.push_back({{30.f, -2.f, 0.f}, {31.f, 4.f, 3.f}});
        aWorld.walls.push_back({{-100.f, 25.f, 0.f}, {100.f, 28.f, 60.f}});   // the building across the courtyard
    };
    const RoomSound balcony = measure("balcony", buildBalcony, {0.f, 2.f, 1.6f});
    const RoomSound balconyEdge = measure("balcony, by the wall", buildBalcony, {10.f, 0.5f, 1.6f});
    // A hole in a room: a doorway to the street shouldn't turn it into a street.
    const RoomSound roomWithDoor = measure("room with a doorway", [](FakeWorld& aWorld) {
        aWorld.walls.push_back({{-100.f, -100.f, -1.f}, {100.f, 100.f, 0.f}});
        aWorld.walls.push_back({{0.f, 0.f, 3.f}, {6.f, 6.f, 4.f}});
        aWorld.walls.push_back({{-1.f, 0.f, 0.f}, {0.f, 6.f, 3.f}});
        aWorld.walls.push_back({{6.f, 0.f, 0.f}, {7.f, 6.f, 3.f}});
        aWorld.walls.push_back({{0.f, -1.f, 0.f}, {6.f, 0.f, 3.f}});
        aWorld.walls.push_back({{0.f, 6.f, 0.f}, {2.2f, 7.f, 3.f}});
        aWorld.walls.push_back({{3.8f, 6.f, 0.f}, {6.f, 7.f, 3.f}});
    }, {3.f, 3.f, 1.6f});


    Check(closet.decaySeconds < 0.35f, "a closet dies fast", "%.2f s", closet.decaySeconds);
    Check(room.decaySeconds > closet.decaySeconds && room.decaySeconds < 1.f, "a room rings a little longer", "%.2f s", room.decaySeconds);
    Check(hall.decaySeconds > 1.5f, "a hall rings", "%.2f s", hall.decaySeconds);
    Check(tunnel.decaySeconds > 1.2f && tunnel.decaySeconds > room.decaySeconds * 2.f, "and so does a tunnel, though its ends are out of reach", "%.2f s", tunnel.decaySeconds);
    Check(closet.enclosure > 0.95f && room.enclosure > 0.95f && hall.enclosure > 0.95f, "all closed in");
    Check(tunnel.enclosure > 0.8f, "a tunnel counts as closed too", "%.2f", tunnel.enclosure);
    Check(street.enclosure < 0.4f && street.enclosure > plaza.enclosure, "a street is mostly open, but less so than a plaza", "%.2f", street.enclosure);
    Check(plaza.enclosure < 0.1f, "a plaza gives back almost nothing", "%.2f", plaza.enclosure);
    {
        // An open square full of clutter, with one real building on its north side. Only the building should give an echo.
        Scene scene;
        scene.world.walls.push_back({{-400.f, -400.f, -1.f}, {400.f, 400.f, 0.f}});
        scene.world.walls.push_back({{10.f, -0.15f, 0.f}, {10.3f, 0.15f, 6.f}});       // east: a lamp post
        scene.world.walls.push_back({{-13.f, -1.f, 1.f}, {-12.8f, 1.f, 3.f}});         // west: a small sign
        for (int step = 0; step < 16; ++step)                                          // south: a flight of stairs going up
        {
            const float y = -8.f - static_cast<float>(step) * 0.3f;
            scene.world.walls.push_back({{-30.f, -60.f, 0.f}, {30.f, y, 0.2f * static_cast<float>(step + 1)}});
        }
        scene.world.walls.push_back({{5.f, 5.f, 0.f}, {30.f, 5.3f, 1.8f}});            // north-east: a wall lower than it looks
        scene.world.walls.push_back({{-100.f, 22.f, 0.f}, {4.f, 24.f, 30.f}});         // north and north-west: the building
        scene.listener = {0.f, 0.f, 1.6f};
        scene.talker = {3.f, 0.f, 1.6f};
        const RoomSound square = RoomOf(scene);
        const WallSurfaces& walls = scene.acoustics.Walls();
        std::printf("  square with clutter: closed %.2f, rings %.2f s\n", square.enclosure, square.decaySeconds);
        Check(!walls[0].hit, "a lamp post gives no echo");
        Check(!walls[4].hit, "nor a small sign");
        Check(!walls[6].hit, "nor a flight of stairs");
        Check(!walls[1].hit, "nor a low wall");
        Check(walls[2].hit, "while the building across the square does");
        Check(square.enclosure < 0.15f, "and the square gives back almost nothing else", "%.2f", square.enclosure);
        Check(square.decaySeconds < 0.3f, "with no ring to it", "%.2f s", square.decaySeconds);

        // A thing the voice mostly passes through doesn't throw it back.
        Scene hedge;
        hedge.world.walls.push_back({{-400.f, -400.f, -1.f}, {400.f, 400.f, 0.f}});
        hedge.world.walls.push_back({{10.f, -50.f, 0.f}, {11.f, 50.f, 30.f}, ThinWallOcclusion("leaves.physmat")});
        hedge.listener = {0.f, 0.f, 1.6f};
        hedge.talker = {3.f, 0.f, 1.6f};
        RoomOf(hedge);
        Check(!hedge.acoustics.Walls()[0].hit, "nor do leaves");
    }
    {
        // The spots from the solo test, as boxes. Each one sounded wrong in the game.
        const auto measured = [](const char* aName, auto&& aBuild, const Vec3& aStand) {
            Scene scene;
            scene.world.walls.push_back({{-400.f, -400.f, -1.f}, {400.f, 400.f, 0.f}});
            aBuild(scene.world);
            scene.listener = aStand;
            scene.talker = {aStand.x + 1.f, aStand.y, aStand.z};
            const RoomSound found = RoomOf(scene);
            std::printf("  %s: closed %.2f, %.1f m, rings %.2f s\n", aName, found.enclosure, found.meters, found.decaySeconds);
            return found;
        };
        // A sidewalk with a wall beside it, a building's overhang 30 m up, and open road both ways.
        const RoomSound sidewalk = measured("sidewalk under a high overhang", [](FakeWorld& aWorld) {
            aWorld.walls.push_back({{-100.f, 5.f, 0.f}, {100.f, 8.f, 60.f}});
            aWorld.walls.push_back({{-100.f, -10.f, 31.6f}, {100.f, 8.f, 40.f}});
        }, {0.f, 0.f, 1.6f});
        Check(sidewalk.decaySeconds <= 0.5f, "a high overhang doesn't make a sidewalk ring", "%.2f s", sidewalk.decaySeconds);
        Check(sidewalk.enclosure < 0.2f, "and it stays open", "closed %.2f", sidewalk.enclosure);
        // An alley between two walls, sky above.
        const RoomSound alley = measured("alley", [](FakeWorld& aWorld) {
            aWorld.walls.push_back({{-100.f, -3.f, 0.f}, {100.f, -2.f, 60.f}});
            aWorld.walls.push_back({{-100.f, 3.f, 0.f}, {100.f, 4.f, 60.f}});
        }, {0.f, 0.f, 1.6f});
        Check(alley.decaySeconds < 0.4f, "an alley hardly rings", "%.2f s", alley.decaySeconds);
        // A concrete overpass 6 m up and 14 m wide, with open road both ways.
        const RoomSound overpass = measured("overpass", [](FakeWorld& aWorld) {
            aWorld.walls.push_back({{-7.f, -100.f, 6.f}, {7.f, 100.f, 7.f}});
            aWorld.walls.push_back({{-12.f, -100.f, 0.f}, {-11.f, 100.f, 7.f}});
        }, {0.f, 0.f, 1.6f});
        Check(overpass.enclosure > 0.25f, "an overpass gives something back", "closed %.2f", overpass.enclosure);
        Check(overpass.decaySeconds <= 0.7f, "briefly", "%.2f s", overpass.decaySeconds);
        // A ramp recess: roofed all over, walled on three sides, and on the fourth a wall that stops just above head height.
        const RoomSound recess = measured("recess with a low wall", [](FakeWorld& aWorld) {
            aWorld.walls.push_back({{-5.f, -5.f, 4.f}, {5.f, 12.f, 5.f}});
            aWorld.walls.push_back({{-6.f, -6.f, 0.f}, {-5.f, 12.f, 4.f}});
            aWorld.walls.push_back({{5.f, -6.f, 0.f}, {6.f, 12.f, 4.f}});
            aWorld.walls.push_back({{-5.f, -6.f, 0.f}, {5.f, -5.f, 4.f}});
            aWorld.walls.push_back({{-5.f, 4.f, 0.f}, {5.f, 4.3f, 1.8f}});
        }, {0.f, 0.f, 1.6f});
        Check(recess.decaySeconds <= 0.5f && recess.enclosure < 0.6f, "a low wall doesn't seal a recess: sound goes over it", "%.2f s", recess.decaySeconds);
        // Under a huge structure: its underside far overhead, nothing else around.
        const RoomSound underHigh = measured("under a structure 40 m up", [](FakeWorld& aWorld) {
            aWorld.walls.push_back({{-60.f, -60.f, 41.f}, {60.f, 60.f, 50.f}});
        }, {0.f, 0.f, 1.6f});
        Check(underHigh.enclosure < 0.05f && underHigh.decaySeconds <= 0.25f, "a roof that high might as well not exist", "%.2f s", underHigh.decaySeconds);
        // The same room bare and with soft walls.
        const auto roomOf = [&](const char* aName, float aSoft) {
            return measured(aName, [aSoft](FakeWorld& aWorld) {
                aWorld.walls.push_back({{-3.f, -3.f, 3.f}, {3.f, 3.f, 4.f}, 0.f, 0.f});
                aWorld.walls.push_back({{-4.f, -4.f, 0.f}, {-3.f, 4.f, 3.f}, 0.f, aSoft});
                aWorld.walls.push_back({{3.f, -4.f, 0.f}, {4.f, 4.f, 3.f}, 0.f, aSoft});
                aWorld.walls.push_back({{-3.f, -4.f, 0.f}, {3.f, -3.f, 3.f}, 0.f, aSoft});
                aWorld.walls.push_back({{-3.f, 3.f, 0.f}, {3.f, 4.f, 3.f}, 0.f, aSoft});
            }, {0.f, 0.f, 1.6f});
        };
        const RoomSound bare = roomOf("bare room", 0.f);
        const RoomSound padded = roomOf("padded room", SoftSurfaceAbsorbs("fabrics.physmat"));
        Check(padded.decaySeconds < bare.decaySeconds * 0.7f, "soft walls shorten a room's ring", "%.2f s", padded.decaySeconds);
        Check(SoftSurfaceAbsorbs("concrete.physmat") == 0.f && SoftSurfaceAbsorbs("default_material.physmat") == 0.f && SoftSurfaceAbsorbs(nullptr) == 0.f,
              "and hard or unknown surfaces stay as they are");
        // A sleeping alcove open to a field, with some big structure far out over the field.
        const RoomSound alcove = measured("alcove facing open ground", [](FakeWorld& aWorld) {
            aWorld.walls.push_back({{-3.f, -1.5f, 2.4f}, {3.f, 1.5f, 2.7f}});
            aWorld.walls.push_back({{-3.3f, -1.5f, 0.f}, {-3.f, 1.5f, 2.4f}});
            aWorld.walls.push_back({{3.f, -1.5f, 0.f}, {3.3f, 1.5f, 2.4f}});
            aWorld.walls.push_back({{-3.3f, -1.8f, 0.f}, {3.3f, -1.5f, 2.4f}});
            aWorld.walls.push_back({{-100.f, 20.f, 14.f}, {100.f, 100.f, 15.f}});
        }, {0.f, 0.f, 1.6f});
        Check(alcove.decaySeconds <= 0.5f, "a roof far out over open ground doesn't seal an alcove", "%.2f s", alcove.decaySeconds);
        // A pipe you can stand in, open at both ends. Round enough for boxes: walls, floor and roof close around you.
        const RoomSound pipe = measured("pipe", [](FakeWorld& aWorld) {
            aWorld.walls.push_back({{-3.f, -1.3f, 0.f}, {3.f, -1.f, 2.4f}});
            aWorld.walls.push_back({{-3.f, 1.f, 0.f}, {3.f, 1.3f, 2.4f}});
            aWorld.walls.push_back({{-3.f, -1.3f, 2.4f}, {3.f, 1.3f, 2.7f}});
        }, {0.f, 0.f, 1.6f});
        Check(pipe.enclosure > 0.45f, "a pipe stays closed in, though both ends are open", "closed %.2f", pipe.enclosure);
    }
    Check(balcony.enclosure < 0.65f && balcony.enclosure < tunnel.enclosure * 0.7f, "a balcony isn't a tunnel, though rays hit the ceiling and the building opposite", "closed %.2f", balcony.enclosure);
    Check(balcony.decaySeconds < 0.5f, "and sound leaves through its open side instead of ringing", "%.2f s", balcony.decaySeconds);
    Check(std::fabs(balconyEdge.decaySeconds - balcony.decaySeconds) < 0.25f, "wherever you stand on it", "%.2f s", balconyEdge.decaySeconds);
    Check(roomWithDoor.enclosure > 0.6f && roomWithDoor.decaySeconds < 0.9f, "a room with its door open is still a room", "closed %.2f", roomWithDoor.enclosure);


    {
        // Nothing depends on the camera any more, so this only has to hold for where you stand.
        Scene scene;
        scene.world.AddHollow({0.f, 0.f, 0.f}, {5.f, 5.f, 3.f});
        scene.listener = {2.5f, 2.5f, 1.6f};
        scene.talker = {3.5f, 2.5f, 1.6f};
        scene.Run(1.f);
        int walls = 0;
        for (const WallSurface& wall : scene.acoustics.Walls())
        {
            walls += wall.hit ? 1 : 0;
            Check(!wall.hit || std::fabs(wall.normal.z) < 0.01f, "walls found are walls, not the floor");
        }
        Check(walls == kWallDirections, "every direction finds a wall", "%.0f", walls);
    }
    {
        // If the game's normals turn out empty, walls are taken to face the ray that found them.
        Scene scene;
        scene.world.normals = false;
        scene.world.AddHollow({0.f, 0.f, 0.f}, {5.f, 5.f, 3.f});
        scene.listener = {2.5f, 2.5f, 1.6f};
        scene.talker = {3.5f, 2.5f, 1.6f};
        scene.Run(1.f);
        const WallSurface& east = scene.acoustics.Walls()[0];
        Check(east.hit && east.normal.x < -0.99f, "with no normal from the game, the ray's direction stands in", "%.2f", east.normal.x);
    }
}

void TestWallsBetween()
{
    std::printf("what's between two players\n");
    Check(ThinWallOcclusion("concrete.physmat") == 0.f && ThinWallOcclusion("default_material.physmat") == 0.f && ThinWallOcclusion(nullptr) == 0.f,
          "most materials count as solid");
    Check(ThinWallOcclusion("glass.physmat") > ThinWallOcclusion("metal_transparent.physmat") && ThinWallOcclusion("metal_transparent.physmat") > 0.f,
          "a window stops more than a grate, and both far less than a wall");

    const auto between = [](auto&& aBuild, float aSeparation = 6.f) {
        Scene scene;
        aBuild(scene.world);
        scene.listener = {0.f, 0.f, 1.6f};
        scene.talker = {aSeparation, 0.f, 1.6f};
        scene.Run(1.f);
        return scene.acoustics.Occlusion(1);
    };
    const float big = 4.f; // wider than the spread of the five lines
    const float clear = between([](FakeWorld&) {});
    const float thinWall = between([&](FakeWorld& aWorld) { aWorld.walls.push_back({{3.f, -big, -big}, {3.2f, big, big}}); });
    const float building = between([&](FakeWorld& aWorld) { aWorld.walls.push_back({{1.f, -big, -big}, {5.f, big, big}}); });
    const float door = between([&](FakeWorld& aWorld) { aWorld.doors.push_back({{3.f, -big, -big}, {3.1f, big, big}}); });
    const float window = between([&](FakeWorld& aWorld) { aWorld.walls.push_back({{3.f, -big, -big}, {3.05f, big, big}, ThinWallOcclusion("glass.physmat")}); });
    const float grate = between([&](FakeWorld& aWorld) { aWorld.walls.push_back({{3.f, -big, -big}, {3.05f, big, big}, ThinWallOcclusion("metal_transparent.physmat")}); });
    const float windowInWall = between([&](FakeWorld& aWorld) {
        aWorld.walls.push_back({{3.f, -big, -big}, {3.05f, big, big}, ThinWallOcclusion("glass.physmat")});
        aWorld.walls.push_back({{4.f, -big, -big}, {4.2f, big, big}});
    });
    std::printf("  clear %.2f, grate %.2f, window %.2f, door %.2f, thin wall %.2f, window before a wall %.2f, building %.2f\n", clear, grate, window, door,
                thinWall, windowInWall, building);
    Check(clear == 0.f, "a clear line is clear");
    Check(door > 0.5f && door < 0.6f, "a closed door counts as it always has", "%.2f", door);
    Check(thinWall >= 0.6f && thinWall < 0.75f, "and so does a thin wall", "%.2f", thinWall);
    Check(building > thinWall + 0.15f, "and a whole building more than that", "%.2f", building);
    Check(window > 0.2f && window < door, "a window muffles less than a door", "%.2f", window);
    Check(grate > 0.f && grate < 0.15f, "and a grate hardly at all", "%.2f", grate);
    Check(windowInWall >= thinWall, "a window with a wall behind it is still a wall", "%.2f", windowInWall);

    // What doesn't get measured.
    {
        Scene scene;
        scene.world.walls.push_back({{20.f, -big, -big}, {21.f, big, big}});
        scene.listener = {0.f, 0.f, 1.6f};
        scene.talker = {55.f, 0.f, 1.6f};
        scene.Run(1.f);
        const int roomRaysOnly = scene.world.rays;
        Check(roomRaysOnly <= 84, "a player out of earshot costs no rays of their own, only the room's", "%.0f rays in a second", roomRaysOnly);
    }
    {
        Scene scene;
        scene.world.walls.push_back({{3.f, -big, -big}, {3.2f, big, big}});
        scene.listener = {0.f, 0.f, 1.6f};
        scene.talker = {6.f, 0.f, 1.6f};
        scene.cabin = CabinShared;
        scene.Run(1.f);
        Check(scene.acoustics.Occlusion(1) == 0.f, "nor does someone in your own vehicle");
    }
    {
        // A quiet player's walls stay current, more slowly. The first word then has the right walls.
        Scene scene;
        scene.world.walls.push_back({{3.f, -big, -big}, {3.2f, big, big}});
        scene.listener = {0.f, 0.f, 1.6f};
        scene.talker = {6.f, 0.f, 1.6f};
        scene.talking = false;
        scene.Run(1.5f);
        const float quiet = scene.acoustics.Occlusion(1);
        Check(quiet >= 0.6f, "a quiet player's walls are still known", "%.2f", quiet);
        const int rays = scene.world.rays;
        scene.Run(5.f);
        Check((scene.world.rays - rays) / 5 < 100, "and add few rays to the room's", "%.0f a second", (scene.world.rays - rays) / 5);
    }
}

void TestWaysRound()
{
    std::printf("ways round a corner\n");

    // Two corridors in an L. The listener's in one and the talker's round the corner in the other. Nobody has walked it.
    const auto buildEll = [](FakeWorld& aWorld) {
        aWorld.walls.push_back({{-50.f, -50.f, -1.f}, {50.f, 50.f, 0.f}});
        aWorld.walls.push_back({{-50.f, -50.f, 3.f}, {50.f, 50.f, 4.f}});
        aWorld.walls.push_back({{-3.f, -3.f, 0.f}, {16.f, 0.f, 3.f}});    // south side of the east-west corridor
        aWorld.walls.push_back({{-3.f, 0.f, 0.f}, {0.f, 3.f, 3.f}});      // its west end
        aWorld.walls.push_back({{-3.f, 3.f, 0.f}, {10.f, 30.f, 3.f}});    // the block inside the L
        aWorld.walls.push_back({{13.f, 0.f, 0.f}, {16.f, 30.f, 3.f}});    // east side of the north-south corridor
        aWorld.walls.push_back({{-3.f, 30.f, 0.f}, {16.f, 33.f, 3.f}});   // its north end
    };
    {
        Scene scene;
        buildEll(scene.world);
        scene.listener = {2.f, 1.5f, 1.6f};
        scene.talker = {11.5f, 15.f, 1.6f};
        scene.Run(0.5f);
        Check(scene.acoustics.Occlusion(1) > 0.5f, "walls stand between them");
        scene.Run(8.f);
        const SoundPath path = scene.acoustics.Path(1);
        const float straight = std::hypot(9.5f, 13.5f);
        Check(path.found, "a fan of rays finds the corner when nobody has walked it");
        Check(path.meters >= straight && path.meters < straight * 1.5f, "the way round is about the length of the corridors", "%.1f m", path.meters);
        Check(path.bends == 1.f, "with one bend", "%.0f", path.bends);
        Check(path.arrival.x > 6.f && path.arrival.y < 3.f, "and the voice comes from down the corridor, where the corner is", "%.1f m along", path.arrival.x);
    }
    {
        // The talker walks round the corner while the listener watches. Now it's known straight away.
        Scene scene;
        buildEll(scene.world);
        scene.listener = {2.f, 1.5f, 1.6f};
        scene.talker = {6.f, 1.5f, 1.6f};
        scene.Run(0.5f);
        scene.Walk(scene.talker, {11.5f, 1.5f, 1.6f});
        scene.Walk(scene.talker, {11.5f, 15.f, 1.6f});
        scene.Run(0.5f);
        const SoundPath path = scene.acoustics.Path(1);
        Check(path.found, "their trail shows the way as they walk it");
        Check(path.meters > 20.f && path.meters < 26.f, "at about the right length", "%.1f m", path.meters);
        Check(path.arrival.y < 3.f, "with the first bend in the listener's corridor", "%.1f m", path.arrival.y);
        // Keeping it costs little, while it's still true.
        const int rays = scene.world.rays;
        scene.Run(5.f);
        const int perSecond = (scene.world.rays - rays) / 5;
        Check(scene.acoustics.Path(1).found, "and it stays found");
        Check(perSecond < 120, "cheaply", "%.0f rays a second", perSecond);
    }
    {
        // It's the listener who walks away this time.
        Scene scene;
        buildEll(scene.world);
        scene.listener = {6.f, 1.5f, 1.6f};
        scene.talker = {2.f, 1.5f, 1.6f};
        scene.Run(0.5f);
        scene.Walk(scene.listener, {11.5f, 1.5f, 1.6f});
        scene.Walk(scene.listener, {11.5f, 15.f, 1.6f});
        scene.Run(1.f);
        const SoundPath path = scene.acoustics.Path(1);
        Check(path.found, "the listener's own trail works the same way");
        Check(path.arrival.y < 14.f && path.arrival.x > 10.f, "and the voice comes from back the way they came", "%.1f m", path.arrival.y);
        Check(path.meters > 20.f && path.meters < 26.f, "at about the right length", "%.1f m", path.meters);
    }

    // Room, door, hallway, door, room: two bends, which only a trail can find.
    const auto buildRooms = [](FakeWorld& aWorld) {
        aWorld.walls.push_back({{-50.f, -50.f, -1.f}, {50.f, 50.f, 0.f}});
        aWorld.walls.push_back({{-50.f, -50.f, 3.f}, {50.f, 50.f, 4.f}});
        aWorld.walls.push_back({{-1.f, -1.f, 0.f}, {21.f, 0.f, 3.f}});    // south wall of both rooms
        aWorld.walls.push_back({{-1.f, 0.f, 0.f}, {0.f, 12.f, 3.f}});     // west
        aWorld.walls.push_back({{20.f, 0.f, 0.f}, {21.f, 12.f, 3.f}});    // east
        aWorld.walls.push_back({{9.f, 0.f, 0.f}, {11.f, 6.f, 3.f}});      // between the rooms
        // The wall between rooms and hallway, gaps at x 4 to 6 and x 14 to 16.
        aWorld.walls.push_back({{0.f, 6.f, 0.f}, {4.f, 7.f, 3.f}});
        aWorld.walls.push_back({{6.f, 6.f, 0.f}, {14.f, 7.f, 3.f}});
        aWorld.walls.push_back({{16.f, 6.f, 0.f}, {20.f, 7.f, 3.f}});
        aWorld.walls.push_back({{-1.f, 10.f, 0.f}, {21.f, 11.f, 3.f}});   // north of the hallway
    };
    {
        Scene scene;
        buildRooms(scene.world);
        scene.listener = {5.f, 3.f, 1.6f};
        scene.talker = {5.f, 2.f, 1.6f};
        scene.Run(0.3f);
        scene.Walk(scene.talker, {5.f, 8.5f, 1.6f});
        scene.Walk(scene.talker, {15.f, 8.5f, 1.6f});
        scene.Walk(scene.talker, {15.f, 3.f, 1.6f});
        scene.Run(0.5f);
        const SoundPath path = scene.acoustics.Path(1);
        Check(path.found, "two corners, through a hallway, once somebody has walked it");
        Check(path.bends >= 2.f, "with the bends counted", "%.0f", path.bends);
        Check(path.meters > 18.f && path.meters < 26.f, "and the length along the hallway", "%.1f m", path.meters);
        Check(path.arrival.x > 3.f && path.arrival.x < 7.f && path.arrival.y > 4.f, "and the voice comes through the door they left by", "%.1f m", path.arrival.y);
        Check(path.doors == 0.f, "with no closed doors on the way");

        // Now someone shuts the door behind them.
        scene.world.doors.push_back({{14.f, 6.f, 0.f}, {16.f, 6.2f, 3.f}});
        scene.Run(3.f);
        const SoundPath shut = scene.acoustics.Path(1);
        Check(!shut.found || shut.doors >= 1.f, "shutting a door on the way counts", "%.0f doors", shut.doors);
    }
    {
        Scene scene;
        buildRooms(scene.world);
        scene.listener = {5.f, 3.f, 1.6f};
        scene.talker = {15.f, 3.f, 1.6f};
        scene.Run(8.f);
        Check(!scene.acoustics.Path(1).found, "with no trail and two corners, it stays with the wall, as agreed");
    }
    {
        // A fast travel isn't a walk. Two corners, so only a trail could have found this one.
        Scene scene;
        buildRooms(scene.world);
        scene.listener = {5.f, 3.f, 1.6f};
        scene.talker = {5.f, 2.f, 1.6f};
        scene.Run(0.3f);
        scene.talker = {15.f, 3.f, 1.6f};
        scene.Run(3.f);
        Check(!scene.acoustics.Path(1).found, "a teleport leaves no trail behind it");
    }
    {
        // Everything a player can cost at once, two of them talking behind walls with no way round, at the user's frame rate.
        Scene scene;
        buildRooms(scene.world);
        scene.listener = {5.f, 3.f, 1.6f};
        scene.talker = {15.f, 3.f, 1.6f};
        scene.Run(2.f);
        const int rays = scene.world.rays;
        scene.Run(10.f);
        const int perSecond = (scene.world.rays - rays) / 10;
        Check(perSecond < 150, "a talker behind walls with no way round costs a bounded number of rays", "%.0f a second", perSecond);
    }
}

void TestPathSound()
{
    std::printf("how a way round sounds\n");
    SpatialInput input;
    input.listenerForward = {0.f, 1.f, 0.f};
    input.listenerRight = {1.f, 0.f, 0.f};
    input.talkerPosition = {0.f, 10.f, 0.f};
    input.occlusion = 0.8f;
    const SpatialOutput through = ComputeSpatial(input);

    input.pathAmount = 1.f;
    input.pathArrival = {8.f, 0.f, 0.f};
    input.pathMeters = 15.f;
    input.pathBends = 1.f;
    const SpatialOutput around = ComputeSpatial(input);
    const float louder = 20.f * std::log10(std::max(around.gainLeft, around.gainRight) / through.gainLeft);
    Check(louder > 3.f, "an open way round is louder than the wall", "%+.1f dB", louder);
    Check(around.lowpassHz > through.lowpassHz, "and clearer", "%.0f Hz", around.lowpassHz);
    Check(around.gainRight > around.gainLeft * 1.3f, "and comes from the corner, not through the wall", "%.2f", around.gainRight / around.gainLeft);

    input.pathDoors = 1.f;
    const SpatialOutput shutDoor = ComputeSpatial(input);
    Check(shutDoor.gainRight < around.gainRight * 0.8f && shutDoor.lowpassHz < around.lowpassHz, "a closed door on the way muffles it", "%.0f Hz", shutDoor.lowpassHz);
    input.pathDoors = 0.f;

    input.pathMeters = 60.f;
    const SpatialOutput tooLong = ComputeSpatial(input);
    Check(std::fabs(tooLong.gainRight - through.gainRight) < 0.01f, "a way past the far limit adds nothing");
    input.pathMeters = 15.f;

    // Sliding between the two, what's heard mustn't jump.
    float biggestStep = 0.f;
    float previous = through.gainLeft;
    float previousSide = 0.f;
    float biggestSideStep = 0.f;
    for (int i = 0; i <= 100; ++i)
    {
        input.pathAmount = static_cast<float>(i) / 100.f;
        const SpatialOutput step = ComputeSpatial(input);
        biggestStep = std::max(biggestStep, std::fabs(step.gainLeft - previous));
        const float side = (step.gainRight - step.gainLeft) / (step.gainRight + step.gainLeft);
        biggestSideStep = std::max(biggestSideStep, std::fabs(side - previousSide));
        previous = step.gainLeft;
        previousSide = side;
    }
    Check(biggestStep < 0.01f && biggestSideStep < 0.04f, "and blending between them doesn't jump", "%.3f at most", biggestSideStep);

    // Even when the path and the wall are about equal, a small change makes a small difference.
    input.pathAmount = 1.f;
    input.occlusion = 0.25f;
    input.pathMeters = 11.f;
    const SpatialOutput equalish = ComputeSpatial(input);
    input.pathMeters = 11.2f;
    const SpatialOutput equalish2 = ComputeSpatial(input);
    Check(std::fabs(equalish.gainRight - equalish2.gainRight) < 0.02f, "nor does it flip when both are about as loud");
    input.occlusion = 0.8f;

    // No way round makes a difference to who sends to whom.
    input.pathAmount = 0.f;
    const bool sendsPlain = ComputeSpatial(input).audible;
    input.pathAmount = 1.f;
    Check(ComputeSpatial(input).audible == sendsPlain, "and it doesn't change whether anyone sends");
    Check(ShouldSendNearby(39.f, 0.f, false, 40.f) && !ShouldSendNearby(41.f, 0.f, false, 40.f), "sending goes by straight-line distance");
    Check(ShouldSendNearby(3.f, 1.f, false, 40.f) && !ShouldSendNearby(6.f, 1.f, false, 40.f) && ShouldSendNearby(6.f, 0.5f, false, 40.f), "and whether a car's in the way, which can't be heard past 5 m");
    Check(ShouldSendNearby(30.f, 1.f, true, 40.f) && !ShouldSendNearby(41.f, 1.f, true, 40.f), "unless the car has a gap, when the far limit is all");

    PathEase ease;
    ease.Update(false, {}, 0.f, 0.f, 0.f, 100000.0);
    Check(ease.Amount() == 0.f, "no way round to start with");
    double now = 100000.0;
    for (int i = 0; i < 3; ++i)
    {
        now += 33.0;
        ease.Update(true, {10.f, 0.f, 0.f}, 20.f, 1.f, 0.f, now);
    }
    Check(ease.Amount() > 0.2f && ease.Amount() < 0.5f, "one found comes in over a third of a second", "%.2f", ease.Amount());
    Check(ease.Arrival().x == 10.f, "from where it's been found, with no slide across the room");
    for (int i = 0; i < 20; ++i)
    {
        now += 33.0;
        ease.Update(true, {10.f, 0.f, 0.f}, 20.f, 1.f, 0.f, now);
    }
    Check(ease.Amount() == 1.f, "and stays");
    now += 33.0;
    ease.Update(true, {0.f, 10.f, 0.f}, 20.f, 1.f, 0.f, now);
    Check(ease.Arrival().x > 7.f && ease.Arrival().y < 3.f, "a better corner glides in instead of jumping", "%.1f", ease.Arrival().x);
    now += 33.0;
    ease.Update(false, {}, 0.f, 0.f, 0.f, now);
    Check(ease.Amount() > 0.8f && ease.Meters() == 20.f, "and one lost fades, from where it was");
}

// A Mizutani Hozuki as the car probe found it on 2026-11-13: each glass and door part's mesh, and where the game put it
// with everything shut, in the car's frame (right, forward, up).
struct FakePart
{
    int glass;
    int door;
    const char* name;
    uint64_t mesh;
    Vec3 pivot;
};

const FakePart kHozuki[] = {
    {0, -1, "window_f", 12278391241719043876ull, {0.f, 0.f, 0.40f}},
    {1, -1, "window_fl", 16234536973204584184ull, {-0.81f, 0.59f, 0.64f}},
    {2, -1, "window_fr", 14113000640040682594ull, {0.81f, 0.59f, 0.64f}},
    {3, -1, "window_bl", 14228558100944804188ull, {-0.81f, -0.68f, 0.68f}},
    {4, -1, "window_br", 1472569933064663054ull, {0.81f, -0.68f, 0.68f}},
    {5, -1, "window_bl_02", 16343010582634198051ull, {-0.94f, -0.37f, 0.32f}},
    {6, -1, "window_br_02", 10406851649055857633ull, {0.94f, -0.37f, 0.32f}},
    {7, -1, "trunk_a_window_01", 1509337683122292238ull, {-0.55f, -1.22f, 1.02f}},
    {-1, 0, "door_fl_a", 11534028905857495944ull, {-0.96f, 0.79f, 0.29f}},
    {-1, 1, "door_fr_a", 4083839359777836626ull, {0.96f, 0.79f, 0.29f}},
    {-1, 2, "door_bl_a", 11371938853316775724ull, {-0.94f, -0.37f, 0.32f}},
    {-1, 3, "door_br_a", 16531046409370485118ull, {0.94f, -0.37f, 0.32f}},
};
const Vec3 kHozukiDriverHead{-0.39f, -0.10f, 0.78f}; // the NPC driver's head the probe read

void BuildHozuki(Car& aCar, uint32_t aKey, const char* aAppearance = "mizutani_hozuki__basic_default")
{
    aCar.Begin(aKey);
    for (const FakePart& part : kHozuki)
    {
        aCar.AddPart(part.glass, part.door, part.name, part.mesh, part.pivot);
    }
    aCar.Finish(aAppearance);
}

void DescribeHozuki(Engine& aEngine, PeerId aOwner, uint32_t aKey)
{
    aEngine.BeginCar(aOwner, aKey);
    for (const FakePart& part : kHozuki)
    {
        aEngine.AddCarPart(aOwner, part.glass, part.door, part.name, part.mesh, part.pivot);
    }
    aEngine.FinishCar(aOwner, "mizutani_hozuki__basic_default");
}

CarStates WindowDown(int aDoor)
{
    CarStates states;
    states.windowsDown = static_cast<uint8_t>(1u << aDoor);
    return states;
}

const CarOpening* NearestGap(const std::vector<CarOpening>& aGaps, const Vec3& aTo)
{
    const CarOpening* best = nullptr;
    float bestDistance = 1e9f;
    for (const CarOpening& gap : aGaps)
    {
        const float d = std::hypot(gap.centre.x - aTo.x, gap.centre.y - aTo.y, gap.centre.z - aTo.z);
        if (d < bestDistance)
        {
            bestDistance = d;
            best = &gap;
        }
    }
    return best;
}

void TestCars()
{
    std::printf("cars' gaps\n");
    Vec3 min;
    Vec3 max;
    Check(FindCarMeshBox(16234536973204584184ull, min, max) && max.z > 0.3f && min.y < -0.8f,
          "the table has the Hozuki's front left window, as the game files give it");
    Check(!FindCarMeshBox(12345ull, min, max), "and nothing for a mesh it doesn't know");
    Check(IsOpenTopAppearance("villefort_alvarado__basic_valentinos_02") && IsOpenTopAppearance("porsche_911turbo__basic_cabrio_01") &&
              !IsOpenTopAppearance("villefort_alvarado__basic_default"),
          "the Vato and the Porsche cabrio have no roof, a plain Alvarado has");

    Car car;
    BuildHozuki(car, 1);
    Check(car.Described() && car.GapCount() == 12 && !car.OpenTop() && car.UnknownMeshes() == 0,
          "the Hozuki has twelve gaps that can open: eight panes and four doors", "%.0f", car.GapCount());
    CarFrame frame; // standing at the origin, facing +y
    car.Update({}, frame, 100000.0);
    Check(car.Openings().empty(), "shut, nothing is open");

    car.Update(WindowDown(0), frame, 100100.0);
    const float startWinding = car.Openings().empty() ? 0.f : car.Openings()[0].openness;
    car.Update(WindowDown(0), frame, 100600.0);
    const float halfWound = car.Openings().empty() ? 0.f : car.Openings()[0].openness;
    car.Update(WindowDown(0), frame, 101200.0);
    Check(startWinding < 0.2f && halfWound > 0.4f && halfWound < 0.7f && car.Openings().size() == 1 &&
              car.Openings()[0].openness == 1.f,
          "a window winds down over about a second", "%.2f halfway", halfWound);
    const CarOpening& window = car.Openings()[0];
    Check(window.centre.x < -0.6f && window.centre.y > 0.f && window.centre.z > 0.7f && window.centre.z < 1.f && window.normal.x < -0.9f,
          "the driver's window is beside the driver's head and faces left", "%.2f m up", window.centre.z);
    Check(window.area > 0.2f && window.area < 0.45f, "and is about a third of a square metre", "%.2f m2", window.area);

    CarStates shot;
    shot.glassGone = 1u << 6; // the back right quarter pane
    car.Update(shot, frame, 101300.0);
    const CarOpening* quarter = NearestGap(car.Openings(), {0.7f, -1.17f, 0.87f});
    Check(quarter && quarter->openness == 1.f && quarter->area < 0.1f, "shot-out glass is open at once, and a quarter pane is small",
          "%.2f m2", quarter ? quarter->area : 0.f);
    car.Update({}, frame, 104000.0);

    CarStates doorAndWindow;
    doorAndWindow.doorsOpen = 1;
    doorAndWindow.windowsDown = 1;
    car.Update(doorAndWindow, frame, 110000.0);
    Check(car.Openings().size() == 1 && car.Openings()[0].area > 0.9f, "an open door's gap takes its window in", "%.2f m2",
          car.Openings().empty() ? 0.f : car.Openings()[0].area);

    // A driver talking to someone standing outside.
    car.Update(WindowDown(0), frame, 120000.0);
    const Vec3 atWindow{-1.6f, 0.2f, 1.f};
    const Vec3 farSide{1.6f, 0.2f, 1.f};
    const CarSound inLine = ThroughCars(kHozukiDriverHead, atWindow, &car.Openings(), nullptr, 2.f);
    Check(inLine.gain > 0.8f && inLine.cutoffHz > 8000.f, "at the open window you hear the driver nearly as in the open",
          "%.2f", inLine.gain);
    Check(inLine.arrival.x < -0.6f, "and from the window");
    const CarSound across = ThroughCars(kHozukiDriverHead, farSide, &car.Openings(), nullptr, 2.f);
    Check(across.gain < 0.5f * inLine.gain && across.cutoffHz < 0.5f * inLine.cutoffHz,
          "across the car, with the body in the way, it's quieter and duller", "%.2f", across.gain);
    const CarSound back = ThroughCars(atWindow, kHozukiDriverHead, nullptr, &car.Openings(), 2.f);
    Check(std::fabs(back.gain - inLine.gain) < 0.01f, "the way in sounds as the way out", "%.3f", back.gain - inLine.gain);

    car.Update({}, frame, 130000.0);
    CarStates quarterOnly;
    quarterOnly.glassGone = 1u << 5; // back left quarter pane
    car.Update(quarterOnly, frame, 130100.0);
    const CarSound small = ThroughCars(kHozukiDriverHead, atWindow, &car.Openings(), nullptr, 2.f);
    Check(small.gain > 0.f && small.gain < 0.6f * inLine.gain, "a quarter pane lets less through than a window", "%.2f", small.gain);

    CarStates both = WindowDown(0);
    both.windowsDown |= 2;
    car.Update(both, frame, 140000.0);
    const CarSound twoOpen = ThroughCars(kHozukiDriverHead, farSide, &car.Openings(), nullptr, 2.f);
    Check(twoOpen.gain > across.gain * 1.5f, "with the far side's window down too, the far side hears more", "%.2f", twoOpen.gain);

    // Pulled up side by side, driver's window to driver's window.
    Car other;
    BuildHozuki(other, 2);
    CarFrame beside;
    beside.position = {-2.4f, 0.f, 0.f};
    beside.right = {-1.f, 0.f, 0.f};
    beside.forward = {0.f, -1.f, 0.f}; // facing the other way, so its driver's side faces ours
    car.Update(WindowDown(0), frame, 150000.0);
    other.Update({}, beside, 150000.0);
    const Vec3 otherHead{-2.4f + 0.39f, 0.10f, 0.78f};
    const CarSound oneShut = ThroughCars(kHozukiDriverHead, otherHead, &car.Openings(), &other.Openings(), 2.f);
    other.Update(WindowDown(0), beside, 150010.0);
    other.Update(WindowDown(0), beside, 152000.0);
    const CarSound bothOpen = ThroughCars(kHozukiDriverHead, otherHead, &car.Openings(), &other.Openings(), 2.f);
    Check(bothOpen.gain > 0.6f && oneShut.gain < 0.5f * bothOpen.gain && oneShut.cutoffHz <= kCabinWallCutoffHz + 1.f,
          "window to window you can talk; with one shut, its glass muffles it", "%.2f", bothOpen.gain);

    // In the mix: a closed car stays as it was, a gap opens it up and turns the voice towards it.
    SpatialInput input;
    input.listenerPosition = atWindow;
    input.listenerForward = {0.f, 1.f, 0.f};
    input.listenerRight = {1.f, 0.f, 0.f};
    input.talkerPosition = kHozukiDriverHead;
    input.separatedCabin = 1.f;
    const SpatialOutput shut = ComputeSpatial(input);
    Check(shut.lowpassHz <= kCabinWallCutoffHz && shut.carOpenShare == 0.f, "shut, the cabin muffles as before");
    input.carOpenGain = inLine.gain;
    input.carOpenCutoffHz = inLine.cutoffHz;
    input.carOpenArrival = inLine.arrival;
    input.carOpenAny = true;
    const SpatialOutput open = ComputeSpatial(input);
    const float louder = std::max(open.gainLeft, open.gainRight) / std::max(shut.gainLeft, shut.gainRight);
    Check(louder > 1.6f && open.lowpassHz > 4000.f && shut.lowpassHz <= kCabinWallCutoffHz && open.carOpenShare > 0.7f,
          "the open window brings the voice out clear, where the shut one lets only a murmur through", "%.1f times as loud", louder);
    Check(open.gainRight > open.gainLeft, "and from the window, on the listener's right");
    input.talkerPosition = {-30.f, 0.2f, 1.f};
    input.listenerPosition = kHozukiDriverHead;
    Check(ComputeSpatial(input).audible, "with a gap, a voice is sent past the cabin's 5 m");
    input.carOpenAny = false;
    Check(!ComputeSpatial(input).audible, "without one it isn't, as before");

    Car vato;
    BuildHozuki(vato, 3, "villefort_alvarado__basic_valentinos_02"); // the Hozuki's parts, with the Vato's missing roof
    CarStates noRoof;
    noRoof.openTop = true;
    vato.Update(noRoof, frame, 160000.0);
    const CarOpening* roof = NearestGap(vato.Openings(), {0.f, 0.f, 1.2f});
    Check(vato.OpenTop() && roof && roof->normal.z > 0.9f && roof->area > 1.f, "a car with no roof has its whole top open",
          "%.2f m2", roof ? roof->area : 0.f);
    const CarSound overTop = ThroughCars(kHozukiDriverHead, farSide, &vato.Openings(), nullptr, 2.f);
    Check(overTop.gain > across.gain, "and is heard across it better than through a far window");
}

void TestEchoes()
{
    std::printf("echoes\n");
    WallSurfaces walls{};
    const Vec3 right{1.f, 0.f, 0.f};
    const auto wallAt = [&](int aDirection, const Vec3& aPoint, const Vec3& aNormal) {
        walls[static_cast<size_t>(aDirection)] = {true, aPoint, aNormal};
    };
    const auto strongest = [](const EchoSet& aSet) {
        EchoTap best;
        for (const EchoTap& tap : aSet)
        {
            if (std::max(tap.gainLeft, tap.gainRight) > std::max(best.gainLeft, best.gainRight))
            {
                best = tap;
            }
        }
        return best;
    };

    // A wall 20 m to the right, and a talker 5 m ahead.
    wallAt(0, {20.f, 0.f, 0.f}, {-1.f, 0.f, 0.f});
    const Vec3 listener{0.f, 0.f, 1.6f};
    const Vec3 talker{0.f, 5.f, 1.6f};
    const EchoTap echo = strongest(ComputeEchoes(walls, listener, right, talker, 1.f, true));
    const float bounced = std::hypot(40.f, 5.f);
    const float expected = (bounced - 5.f) / 343.f * kRate;
    Check(std::fabs(echo.delaySamples - expected) < 2.f, "a wall gives an echo as late as the extra distance", "%.0f ms", echo.delaySamples / kRate * 1000.f);
    Check(echo.gainRight > echo.gainLeft * 1.5f && echo.lagLeft > 10.f, "from the wall's direction", "%.2f", echo.gainRight / echo.gainLeft);
    const float heardDb = 20.f * std::log10(std::max(echo.gainLeft, echo.gainRight) / RolloffGain(5.f, 2.f));
    Check(heardDb > -24.f && heardDb < -12.f, "quiet against the voice, but there", "%.1f dB", heardDb);

    // Nearer walls are heard as the room, not as echoes.
    WallSurfaces closeBy{};
    closeBy[0] = {true, {1.5f, 0.f, 1.6f}, {-1.f, 0.f, 0.f}};
    Check(strongest(ComputeEchoes(closeBy, listener, right, talker, 1.f, true)).gainRight == 0.f, "a wall close by gives no echo of its own: that would just comb");

    WallSurfaces between{};
    between[0] = {true, {3.f, 0.f, 1.6f}, {-1.f, 0.f, 0.f}};
    Check(strongest(ComputeEchoes(between, listener, right, {8.f, 0.f, 1.6f}, 1.f, true)).gainRight == 0.f, "a talker behind a wall can't bounce off it");

    WallSurfaces offEnd{};
    offEnd[0] = {true, {12.f, 0.f, 1.6f}, {-1.f, 0.f, 0.f}};
    Check(strongest(ComputeEchoes(offEnd, listener, right, {0.f, 100.f, 1.6f}, 1.f, true)).gainRight == 0.f, "nor off a wall that may not reach that far");
    Check(strongest(ComputeEchoes(walls, listener, right, talker, 0.f, true)).gainRight == 0.f, "walls in the way, a car or water take them away");

    // Walking along, each echo's delay changes smoothly, in the same slot.
    wallAt(4, {-18.f, 0.f, 0.f}, {1.f, 0.f, 0.f});
    EchoSet previous = ComputeEchoes(walls, listener, right, talker, 1.f, true);
    float biggest = 0.f;
    for (int i = 1; i <= 100; ++i)
    {
        const Vec3 walked{static_cast<float>(i) * 0.1f, 0.f, 1.6f};
        const EchoSet now = ComputeEchoes(walls, walked, right, {walked.x, 5.f, 1.6f}, 1.f, true);
        for (size_t slot = 0; slot < now.size(); ++slot)
        {
            if (previous[slot].gainLeft > 0.f && now[slot].gainLeft > 0.f)
            {
                biggest = std::max(biggest, std::fabs(now[slot].delaySamples - previous[slot].delaySamples));
            }
        }
        previous = now;
    }
    Check(biggest < 40.f, "walking along, an echo's delay moves in small steps, in its own slot", "%.1f samples", biggest);

    const EchoTap speakers = strongest(ComputeEchoes(walls, listener, right, talker, 1.f, false));
    Check(speakers.lagLeft == 0.f && speakers.lagRight == 0.f, "with Headphones off they're a plain pan");
}

void TestRoomReverb()
{
    std::printf("the room's sound\n");

    const auto impulse = [](const RoomSound& aRoom, float aSeconds) {
        RoomReverb reverb;
        reverb.SetRoom(aRoom);
        Rendered out;
        std::vector<float> send(kBlock, 0.f);
        float left[kBlock];
        float right[kBlock];
        for (int block = 0; block < static_cast<int>(aSeconds * kRate) / kBlock; ++block)
        {
            std::fill(send.begin(), send.end(), 0.f);
            if (block == 0)
            {
                send[0] = 1.f;
            }
            std::memset(left, 0, sizeof(left));
            std::memset(right, 0, sizeof(right));
            reverb.Process(send.data(), left, right, kBlock);
            out.left.insert(out.left.end(), left, left + kBlock);
            out.right.insert(out.right.end(), right, right + kBlock);
        }
        return out;
    };
    const auto energyDb = [](const std::vector<float>& aSignal) {
        double sum = 0.0;
        for (const float sample : aSignal)
        {
            sum += static_cast<double>(sample) * sample;
        }
        return static_cast<float>(10.0 * std::log10(std::max(sum, 1e-12)));
    };
    // From the point the sound starts falling until it's lost 30 dB, doubled: the usual way to read a decay time.
    const auto measuredDecay = [](const std::vector<float>& aSignal) {
        std::vector<double> remaining(aSignal.size() + 1, 0.0);
        for (size_t i = aSignal.size(); i-- > 0;)
        {
            remaining[i] = remaining[i + 1] + static_cast<double>(aSignal[i]) * aSignal[i];
        }
        size_t from = 0;
        size_t to = 0;
        for (size_t i = 0; i < aSignal.size(); ++i)
        {
            const double db = 10.0 * std::log10(std::max(remaining[i] / remaining[0], 1e-20));
            if (from == 0 && db < -5.0)
            {
                from = i;
            }
            if (to == 0 && db < -35.0)
            {
                to = i;
                break;
            }
        }
        return static_cast<float>(to - from) / kRate * 2.f;
    };

    RoomSound closed;
    closed.enclosure = 1.f;
    closed.meters = 2.f;
    for (const float decay : {0.3f, 0.6f, 1.2f})
    {
        closed.decaySeconds = decay;
        const float seconds = measuredDecay(impulse(closed, decay * 3.f).left);
        Check(seconds > decay * 0.45f && seconds < decay * 1.3f, "a small room rings about as long as measured", "%.2f s", seconds);
    }
    closed.meters = 20.f;
    for (const float decay : {0.6f, 1.5f, 3.f})
    {
        closed.decaySeconds = decay;
        const float seconds = measuredDecay(impulse(closed, decay * 3.f).left);
        Check(seconds > decay * 0.45f && seconds < decay * 1.3f, "and a big space", "%.2f s", seconds);
    }

    closed.meters = 2.f;
    closed.decaySeconds = 0.3f;
    const float shortDb = energyDb(impulse(closed, 2.f).left);
    closed.decaySeconds = 1.2f;
    const float longDb = energyDb(impulse(closed, 6.f).left);
    closed.meters = 20.f;
    closed.decaySeconds = 3.f;
    const float bigDb = energyDb(impulse(closed, 9.f).left);
    std::printf("  tail energy against the sound that made it: short %.1f dB, long %.1f dB, big %.1f dB\n", shortDb, longDb, bigDb);
    Check(std::fabs(longDb - shortDb) < 3.f, "ringing longer doesn't make it louder", "%.1f dB", longDb - shortDb);
    Check(std::fabs(bigDb - shortDb) < 4.f, "and neither does a bigger space", "%.1f dB", bigDb - shortDb);
    Check(std::fabs(shortDb + 18.f) < 3.f, "a closed room gives back about 18 dB under the voice at 2 m", "%.1f dB", shortDb);

    RoomSound open;
    open.enclosure = 0.f;
    open.meters = 36.f;
    open.decaySeconds = 0.6f;
    const float openDb = energyDb(impulse(open, 2.f).left);
    Check(openDb < shortDb - 12.f, "open air gives back far less", "%.1f dB", openDb);

    // A big space with a short decay mustn't be a delay: the sound has to arrive at once, not a tenth of a second later.
    {
        RoomSound shortBig;
        shortBig.enclosure = 0.5f;
        shortBig.meters = 30.f;
        shortBig.decaySeconds = 0.2f;
        const std::vector<float> out = impulse(shortBig, 1.f).left;
        const size_t window = kRate / 100;
        std::vector<double> powers;
        for (size_t start = 0; start + window <= out.size(); start += window)
        {
            double power = 0.0;
            for (size_t i = start; i < start + window; ++i)
            {
                power += static_cast<double>(out[i]) * out[i];
            }
            powers.push_back(power);
        }
        size_t peak = 0;
        for (size_t i = 0; i < powers.size(); ++i)
        {
            peak = powers[i] > powers[peak] ? i : peak;
        }
        double biggestRise = 0.0;
        for (size_t i = peak + 1; i < powers.size() && powers[i] > powers[peak] * 0.001; ++i)
        {
            biggestRise = std::max(biggestRise, powers[i] / std::max(powers[i - 1], 1e-30));
        }
        std::printf("  a short ring, each 10 ms against its peak, dB:");
        for (size_t i = 0; i < std::min<size_t>(powers.size(), 16); ++i)
        {
            std::printf(" %.0f", 10.0 * std::log10(std::max(powers[i] / powers[peak], 1e-9)));
        }
        std::printf("\n");
        Check(peak * 10 <= 70, "a short ring peaks early", "at %.0f ms", static_cast<double>(peak) * 10.0);
        Check(biggestRise < 2.0, "and only dies away after that: nothing comes back later as a repeat of the voice", "swells %.2f times at most", biggestRise);
    }
    // Each ear gets its own sound.
    {
        closed.meters = 8.f;
        closed.decaySeconds = 1.f;
        const Rendered out = impulse(closed, 2.f);
        double both = 0.0;
        double leftSum = 0.0;
        double rightSum = 0.0;
        for (size_t i = 0; i < out.left.size(); ++i)
        {
            both += static_cast<double>(out.left[i]) * out.right[i];
            leftSum += static_cast<double>(out.left[i]) * out.left[i];
            rightSum += static_cast<double>(out.right[i]) * out.right[i];
        }
        const double correlation = std::fabs(both) / std::sqrt(leftSum * rightSum);
        Check(correlation < 0.3, "the two ears hear different sound", "%.2f alike", correlation);
    }

    // Slow motion sweeps the room in a fifth of a second. A tone going in must come out the same pitch.
    {
        RoomReverb reverb;
        RoomSound small;
        small.enclosure = 1.f;
        small.meters = 2.f;
        small.decaySeconds = 0.5f;
        RoomSound large;
        large.enclosure = 1.f;
        large.meters = 20.f;
        large.decaySeconds = 2.2f;
        std::vector<float> heard;
        float send[kBlock];
        float left[kBlock];
        float right[kBlock];
        int sample = 0;
        for (int block = 0; block < 300; ++block)
        {
            reverb.SetRoom(block % 40 < 20 ? small : large);
            for (int i = 0; i < kBlock; ++i, ++sample)
            {
                send[i] = 0.3f * std::sin(2.f * kPi * 1000.f * static_cast<float>(sample) / kRate);
            }
            std::memset(left, 0, sizeof(left));
            std::memset(right, 0, sizeof(right));
            reverb.Process(send, left, right, kBlock);
            heard.insert(heard.end(), left, left + kBlock);
        }
        const float at = Goertzel(heard, 1000.f);
        const float off = std::max(Goertzel(heard, 960.f), Goertzel(heard, 1040.f));
        Check(off < at * 0.1f, "changing the room quickly doesn't bend the pitch", "%.2f off pitch", off / at);
    }
}

void TestRoomInMixer()
{
    std::printf("the room, echoes and your own voice in the mixer (runs in real time)\n");
    // A burst and then silence, so what follows the burst is only what the room and the walls give back.
    std::vector<float> burst(kRate / 2, 0.f);
    for (int i = 0; i < kRate / 5; ++i)
    {
        const float t = static_cast<float>(i) / kRate;
        burst[static_cast<size_t>(i)] = 0.2f * std::sin(2.f * kPi * 700.f * t) + 0.1f * std::sin(2.f * kPi * 2300.f * t);
    }
    const auto frames = EncodeFrames(burst);
    const int burstEnd = kRate / 5 + kFrame * 3; // past the jitter buffer's wait

    const auto tailOf = [&](const Rendered& aOut) {
        const size_t from = static_cast<size_t>(burstEnd);
        return Rms(std::vector<float>(aOut.left.begin() + static_cast<ptrdiff_t>(from), aOut.left.end()));
    };
    const auto spatialAt = [](float aMeters) {
        SpatialInput input;
        input.listenerForward = {0.f, 1.f, 0.f};
        input.listenerRight = {1.f, 0.f, 0.f};
        input.talkerPosition = {0.f, aMeters, 0.f};
        input.enclosure = 1.f;
        return ComputeSpatial(input);
    };
    RoomSound closed;
    closed.enclosure = 1.f;
    closed.meters = 6.f;
    closed.decaySeconds = 0.9f;
    RoomSound open;
    open.enclosure = 0.f;
    open.meters = 36.f;
    open.decaySeconds = 0.6f;

    const auto renderIn = [&](const RoomSound& aRoom, float aMeters) {
        Mixer mixer;
        mixer.AddVoice(1);
        mixer.SetRoom(aRoom);
        mixer.SetSpatial(1, spatialAt(aMeters));
        return RenderThrough(mixer, 1, frames, 0);
    };

    const Rendered inRoom = renderIn(closed, 2.f);
    const Rendered outside = renderIn(open, 2.f);
    const float tailDb = 20.f * std::log10(std::max(tailOf(inRoom), 1e-6f));
    const float openDb = 20.f * std::log10(std::max(tailOf(outside), 1e-6f));
    Check(tailOf(inRoom) > 0.005f, "a voice leaves a tail behind it in a closed room", "%.1f dB", tailDb);
    Check(tailOf(inRoom) > tailOf(outside) * 3.f, "and far less of one outdoors", "%.1f dB", openDb);

    // Across a closed room the voice falls away and the room's sound doesn't.
    const Rendered across = renderIn(closed, 15.f);
    const float directDrop = 20.f * std::log10(spatialAt(15.f).gainLeft / spatialAt(2.f).gainLeft);
    const float tailDrop = 20.f * std::log10(tailOf(across) / tailOf(inRoom));
    Check(directDrop < -8.f && tailDrop > directDrop * 0.5f, "the room stays loud across it while the voice falls", "room %+.1f dB", tailDrop);

    // Turning away and looking away leave the room's sound alone.
    SpatialInput facing;
    facing.listenerForward = {0.f, 1.f, 0.f};
    facing.listenerRight = {1.f, 0.f, 0.f};
    facing.talkerPosition = {0.f, 6.f, 0.f};
    const SpatialOutput ahead = ComputeSpatial(facing);
    facing.talkerForward = {0.f, 1.f, 0.f};
    facing.listenerForward = {0.f, -1.f, 0.f};
    const SpatialOutput dulled = ComputeSpatial(facing);
    Check(dulled.lowpassHz < ahead.lowpassHz * 0.4f && std::fabs(dulled.reverbLowpassHz - ahead.reverbLowpassHz) < 1.f,
          "turning away dulls the voice, not the room", "%.0f Hz", dulled.reverbLowpassHz);

    {
        // A single echo, 150 ms after the voice, on the right.
        Mixer mixer;
        mixer.AddVoice(1);
        mixer.SetRoom(open);
        SpatialOutput noRoom = spatialAt(2.f);
        noRoom.reverbSend = 0.f;
        mixer.SetSpatial(1, noRoom);
        EchoSet echoes{};
        echoes[0].delaySamples = 7200.f;
        echoes[0].gainRight = 0.5f;
        mixer.SetEchoes(1, echoes);
        const Rendered out = RenderThrough(mixer, 1, frames, 0);
        std::vector<float> onset;
        // Where the voice ends in each ear shows the delay between them.
        const auto lastLoud = [](const std::vector<float>& aSignal) {
            size_t last = 0;
            for (size_t i = 0; i < aSignal.size(); ++i)
            {
                if (std::fabs(aSignal[i]) > 0.02f)
                {
                    last = i;
                }
            }
            return static_cast<float>(last);
        };
        const float gap = (lastLoud(out.right) - lastLoud(out.left)) / kRate * 1000.f;
        Check(gap > 130.f && gap < 170.f, "an echo comes back when it should", "%.0f ms", gap);
    }
    {
        // A wall changing suddenly moves an echo a long way. That mustn't click.
        std::vector<float> tone(kRate, 0.f);
        for (int i = 0; i < kRate; ++i)
        {
            tone[static_cast<size_t>(i)] = 0.2f * std::sin(2.f * kPi * 300.f * static_cast<float>(i) / kRate);
        }
        const auto toneFrames = EncodeFrames(tone);
        Mixer mixer;
        mixer.AddVoice(1);
        mixer.SetRoom(open);
        SpatialOutput silentVoice = spatialAt(2.f);
        silentVoice.gainLeft = 0.f;
        silentVoice.gainRight = 0.f;
        silentVoice.reverbSend = 0.1f;
        mixer.SetSpatial(1, silentVoice);
        EchoSet echoes{};
        echoes[0].delaySamples = 2000.f;
        echoes[0].gainLeft = 0.5f;
        mixer.SetEchoes(1, echoes);

        float block[kBlock * 2];
        float biggest = 0.f;
        float previous = 0.f;
        uint16_t sequence = 0;
        int rendered = 0;
        for (const auto& frame : toneFrames)
        {
            mixer.PushPacket(1, sequence, sequence == 0 ? kFlagSpurt : 0, frame.data(), static_cast<int>(frame.size()));
            ++sequence;
            if (sequence == 25)
            {
                echoes[0].delaySamples = 9000.f;
                mixer.SetEchoes(1, echoes);
            }
            for (int b = 0; b < 2; ++b)
            {
                mixer.Render(block);
                for (int i = 0; i < kBlock; ++i, ++rendered)
                {
                    if (rendered > kRate / 4)
                    {
                        biggest = std::max(biggest, std::fabs(block[i * 2] - previous));
                    }
                    previous = block[i * 2];
                }
            }
            const double until = NowMs() + 19.5;
            while (NowMs() < until)
            {
                Sleep(1);
            }
            mixer.SetSpatial(1, silentVoice);
        }
        const float toneStep = 0.2f * 0.5f * 2.f * kPi * 300.f / kRate;
        Check(biggest < toneStep * 4.f, "an echo moving a long way fades across instead of clicking", "%.4f at most", biggest);
    }
    {
        // A voice through a wall brings the room they're in.
        const auto withTheirRoom = [&](float aAmount) {
            Mixer mixer;
            mixer.AddVoice(1);
            mixer.SetRoom(open);
            RoomSound hall;
            hall.enclosure = 1.f;
            hall.meters = 20.f;
            hall.decaySeconds = 2.f;
            mixer.SetTheirRoom(1, hall);
            SpatialOutput walled = spatialAt(4.f);
            walled.reverbSend = 0.f;
            walled.theirRoom = aAmount;
            mixer.SetSpatial(1, walled);
            return RenderThrough(mixer, 1, frames, 0);
        };
        const float without = tailOf(withTheirRoom(0.f));
        const float with = tailOf(withTheirRoom(1.f));
        Check(with > without * 3.f && with > 0.002f, "a voice from another room brings that room's sound", "%.4f", with);
    }
    {
        SpatialInput same;
        same.listenerForward = {0.f, 1.f, 0.f};
        same.listenerRight = {1.f, 0.f, 0.f};
        same.talkerPosition = {0.f, 6.f, 0.f};
        Check(ComputeSpatial(same).theirRoom == 0.f, "across a clear line it doesn't, or your own room would have two tails");
        same.occlusion = 0.6f;
        Check(ComputeSpatial(same).theirRoom == 1.f, "through a wall it does");
        same.sharedCabin = 1.f;
        Check(ComputeSpatial(same).theirRoom == 0.f, "not in the same car");
    }
    {
        // Your own voice: heard in the room, never directly.
        const auto ownVoice = [&](float aAmount) {
            Mixer mixer;
            RoomSound ringing = closed;
            ringing.decaySeconds = 1.6f;
            mixer.SetRoom(ringing);
            mixer.SetOwnEcho(aAmount);
            std::vector<float> speech = FakeSpeech(kRate / 2);
            Rendered out;
            float block[kBlock * 2];
            for (int i = 0; i + kBlock <= static_cast<int>(speech.size()); i += kBlock)
            {
                mixer.PushOwnVoice(speech.data() + i, kBlock);
                mixer.Render(block);
                for (int s = 0; s < kBlock; ++s)
                {
                    out.left.push_back(block[s * 2]);
                }
            }
            return out;
        };
        const Rendered silent = ownVoice(0.f);
        const Rendered heard = ownVoice(1.f);
        Check(Rms(silent.left) == 0.f, "with Headphones off or in a car, you don't hear your own voice at all");
        Check(Rms(heard.left) > 0.002f, "otherwise it comes back from the room", "%.4f", Rms(heard.left));
        const std::vector<float> speech = FakeSpeech(kRate / 2);
        Check(Rms(heard.left) < Rms(speech) * 0.5f, "well under the voice itself");
        float firstMs = -1.f;
        for (size_t i = 0; i < heard.left.size() && firstMs < 0.f; ++i)
        {
            if (std::fabs(heard.left[i]) > 1e-5f)
            {
                firstMs = static_cast<float>(i) / kRate * 1000.f;
            }
        }
        Check(firstMs >= 2.f, "and never straight to your ears", "first sound after %.1f ms", firstMs);

        // Where the room dies quickly, your voice would all come back after your word has ended, so it doesn't come back.
        {
            Mixer quick;
            RoomSound brief = closed;
            brief.decaySeconds = 0.2f;
            quick.SetRoom(brief);
            quick.SetOwnEcho(1.f);
            const std::vector<float> words = FakeSpeech(kRate / 2);
            std::vector<float> back;
            float block[kBlock * 2];
            for (int i = 0; i + kBlock <= static_cast<int>(words.size()); i += kBlock)
            {
                quick.PushOwnVoice(words.data() + i, kBlock);
                quick.Render(block);
                back.insert(back.end(), block, block + kBlock * 2);
            }
            Check(Rms(back) < 0.0005f, "where the room dies at once, your own words don't come back", "rms %.5f", Rms(back));
        }
        // In the open you don't hear yourself come back, however long the number says it rings.
        {
            Mixer outdoors;
            RoomSound square;
            square.enclosure = 0.1f;
            square.meters = 30.f;
            square.decaySeconds = 1.f;
            outdoors.SetRoom(square);
            outdoors.SetOwnEcho(1.f);
            const std::vector<float> words = FakeSpeech(kRate / 2);
            std::vector<float> back;
            float block[kBlock * 2];
            for (int i = 0; i + kBlock <= static_cast<int>(words.size()); i += kBlock)
            {
                outdoors.PushOwnVoice(words.data() + i, kBlock);
                outdoors.Render(block);
                back.insert(back.end(), block, block + kBlock * 2);
            }
            Check(Rms(back) == 0.f, "in the open, your own words don't come back", "rms %.5f", Rms(back));
        }
        // With nothing reading it, it mustn't pile up: when output starts, the room gets what you're saying now.
        const auto afterBacklog = [&](int aBlocks) {
            Mixer mixer;
            mixer.SetRoom(closed);
            mixer.SetOwnEcho(1.f);
            float block[kBlock * 2];
            mixer.Render(block);
            std::vector<float> stale(static_cast<size_t>(kBlock * aBlocks), 0.2f);
            mixer.PushOwnVoice(stale.data(), static_cast<int>(stale.size()));
            std::vector<float> out;
            for (int i = 0; i < 100; ++i)
            {
                mixer.Render(block);
                out.insert(out.end(), block, block + kBlock * 2);
            }
            return Rms(out);
        };
        Check(afterBacklog(30) < afterBacklog(1) * 3.f, "and a backlog of it is dropped rather than played late", "%.2f times one block", afterBacklog(30) / afterBacklog(1));
    }
    {
        // What all of it costs the audio thread: two talkers, both behind walls, in a room.
        Mixer mixer;
        mixer.AddVoice(1);
        mixer.AddVoice(2);
        mixer.SetRoom(closed);
        mixer.SetOwnEcho(1.f);
        mixer.SetTheirRoom(1, closed);
        mixer.SetTheirRoom(2, closed);
        SpatialOutput walled = spatialAt(4.f);
        walled.theirRoom = 1.f;
        EchoSet echoes{};
        for (EchoTap& tap : echoes)
        {
            tap.delaySamples = 5000.f;
            tap.gainLeft = 0.2f;
            tap.gainRight = 0.2f;
        }
        float block[kBlock * 2];
        const int blocks = 500;
        const double start = NowMs();
        for (int i = 0; i < blocks; ++i)
        {
            mixer.SetSpatial(1, walled);
            mixer.SetSpatial(2, walled);
            mixer.SetEchoes(1, echoes);
            mixer.SetEchoes(2, echoes);
            mixer.Render(block);
        }
        const double perBlockMs = (NowMs() - start) / blocks;
        Check(perBlockMs < 1.f, "it all fits easily in the audio thread's 10 ms", "%.3f ms a block", perBlockMs);

    }
}

// Carries setup messages between two engines, like NightCoop's channel would.
void Pump(Engine& aFrom, PeerId aFromId, Engine& aTo)
{
    aFrom.DrainSignals([&](PeerId, const std::vector<uint8_t>& aMessage) {
        aTo.OnSignal(aFromId, aMessage.data(), aMessage.size());
        return true;
    });
}

// What a mic chain sends for speech at this scale, measured over the last four seconds after it has settled.
float MicOutputDb(float aScale)
{
    int error = 0;
    OpusDecoder* decoder = opus_decoder_create(kRate, 1, &error);
    std::vector<float> decoded;
    MicProcessor mic([&](const uint8_t* aOpus, int aSize, bool) {
        float frame[kFrame];
        const int samples = opus_decode_float(decoder, aOpus, aSize, frame, kFrame, 0);
        if (samples > 0)
        {
            decoded.insert(decoded.end(), frame, frame + samples);
        }
    });
    mic.SetGateThreshold(0.f);
    mic.SetAutoGainConfidence(0.f); // the fake speech doesn't convince the voice detector
    mic.SetNoiseRemoval(false);

    std::vector<float> speech = FakeSpeech(kRate * 16, 0.5f);
    for (float& sample : speech)
    {
        sample *= aScale;
    }
    mic.Process(speech.data(), static_cast<int>(speech.size()));
    opus_decoder_destroy(decoder);

    const size_t lastFour = static_cast<size_t>(kRate) * 4;
    if (decoded.size() < lastFour)
    {
        return -100.f;
    }
    // Only while speaking: the pauses between syllables aren't the level of the speech.
    double energy = 0.0;
    size_t counted = 0;
    for (size_t at = decoded.size() - lastFour; at + kBlock <= decoded.size(); at += kBlock)
    {
        double block = 0.0;
        for (size_t i = 0; i < kBlock; ++i)
        {
            block += static_cast<double>(decoded[at + i]) * decoded[at + i];
        }
        if (block / kBlock > 1e-5) // above -50 dB
        {
            energy += block;
            counted += kBlock;
        }
    }
    return counted == 0 ? -100.f : 10.f * static_cast<float>(std::log10(energy / counted));
}

void TestMicLevels()
{
    std::printf("mics even themselves out\n");
    const float quiet = MicOutputDb(0.06f);
    const float normal = MicOutputDb(0.25f);
    const float hot = MicOutputDb(1.f);
    const float spread = std::max({quiet, normal, hot}) - std::min({quiet, normal, hot});
    std::printf("  sent: quiet mic %.1f dB, normal %.1f dB, hot %.1f dB\n", quiet, normal, hot);
    Check(spread < 3.f, "a mic 24 dB quieter than another ends up within 3 dB of it", "%.1f dB spread", spread);
    Check(std::fabs(normal - kNominalSpeechDb) < 3.f, "speech leaves at about the level the listeners expect", "%.1f dB",
          normal);

    // Two mics, one with heavy bass and hum on top of the same speech: they should sound alike, not just read alike.
    {
        const auto speechBandDb = [](const std::vector<float>& aSignal) {
            Biquad high;
            Biquad low;
            high.SetHighpass(300.f);
            low.SetLowpass(4000.f);
            double energy = 0.0;
            for (const float sample : aSignal)
            {
                const float band = low.Process(high.Process(sample));
                energy += static_cast<double>(band) * band;
            }
            return 10.f * static_cast<float>(std::log10(std::max(energy / aSignal.size(), 1e-12)));
        };
        const auto sent = [](bool aBassy) {
            int error = 0;
            OpusDecoder* decoder = opus_decoder_create(kRate, 1, &error);
            std::vector<float> decoded;
            MicProcessor mic([&](const uint8_t* aOpus, int aSize, bool) {
                float frame[kFrame];
                const int samples = opus_decode_float(decoder, aOpus, aSize, frame, kFrame, 0);
                if (samples > 0)
                {
                    decoded.insert(decoded.end(), frame, frame + samples);
                }
            });
            mic.SetGateThreshold(0.f);
            mic.SetAutoGainConfidence(0.f);
            mic.SetNoiseRemoval(false);
            std::vector<float> speech = FakeSpeech(kRate * 16);
            for (size_t i = 0; i < speech.size(); ++i)
            {
                const float t = static_cast<float>(i) / kRate;
                speech[i] *= 0.25f;
                if (aBassy)
                {
                    speech[i] += 0.12f * std::sin(2.f * kPi * 180.f * t) + 0.15f * std::sin(2.f * kPi * 50.f * t);
                }
            }
            mic.Process(speech.data(), static_cast<int>(speech.size()));
            opus_decoder_destroy(decoder);
            return std::vector<float>(decoded.end() - kRate * 4, decoded.end());
        };
        const std::vector<float> clean = sent(false);
        const std::vector<float> bassy = sent(true);
        const float gap = std::fabs(speechBandDb(clean) - speechBandDb(bassy));
        std::printf("  speech band: clean %.1f dB, bassy %.1f dB (whole signal %.1f dB, %.1f dB)\n", speechBandDb(clean),
                    speechBandDb(bassy), 20.f * std::log10(Rms(clean)), 20.f * std::log10(Rms(bassy)));
        Check(gap < 2.5f, "a mic full of bass and hum sends its speech as loud as a clean one", "%.1f dB apart", gap);
    }
    // Once it knows a mic, a quiet sentence shouldn't make it turn up: that's how a voice gets pumped.
    {
        MicProcessor mic([](const uint8_t*, int, bool) {});
        mic.SetGateThreshold(0.f);
        mic.SetAutoGainConfidence(0.f);
        mic.SetNoiseRemoval(false);
        std::vector<float> talking = FakeSpeech(kRate * 12, 0.5f);
        for (float& sample : talking)
        {
            sample *= 0.5f;
        }
        mic.Process(talking.data(), static_cast<int>(talking.size()));
        const float settled = mic.AutoGainDb();
        std::vector<float> softly = FakeSpeech(kRate * 2, 0.5f);
        for (float& sample : softly)
        {
            sample *= 0.2f;
        }
        mic.Process(softly.data(), static_cast<int>(softly.size()));
        Check(mic.AutoGainDb() - settled < 1.5f, "a quiet sentence barely moves a settled auto gain", "%+.1f dB",
              mic.AutoGainDb() - settled);

        std::vector<float> moved = FakeSpeech(kRate * 20, 0.5f);
        for (float& sample : moved)
        {
            sample *= 0.1f;
        }
        const float before = mic.AutoGainDb();
        mic.Process(moved.data(), static_cast<int>(moved.size()));
        Check(mic.AutoGainDb() - before > 10.f, "but a real change, like moving back from the mic, gets learned", "%+.1f dB",
              mic.AutoGainDb() - before);
    }
    // A low gate must not make the automatic gain chase background noise.
    {
        MicProcessor mic([](const uint8_t*, int, bool) {});
        mic.SetGateThreshold(0.f);
        std::mt19937 random(5);
        std::normal_distribution<float> noise(0.f, 0.01f);
        std::vector<float> hiss(kRate * 5);
        for (float& sample : hiss)
        {
            sample = noise(random);
        }
        mic.Process(hiss.data(), static_cast<int>(hiss.size()));
        Check(std::fabs(mic.AutoGainDb()) < 1.f, "room noise with the gate wide open doesn't move the auto gain", "%.1f dB",
              mic.AutoGainDb());
    }
    // A shout comes out much less of a jump than it went in.
    {
        int error = 0;
        OpusDecoder* decoder = opus_decoder_create(kRate, 1, &error);
        std::vector<float> decoded;
        MicProcessor mic([&](const uint8_t* aOpus, int aSize, bool) {
            float frame[kFrame];
            const int samples = opus_decode_float(decoder, aOpus, aSize, frame, kFrame, 0);
            if (samples > 0)
            {
                decoded.insert(decoded.end(), frame, frame + samples);
            }
        });
        mic.SetGateThreshold(0.f);
        mic.SetAutoGainConfidence(0.f);
        mic.SetNoiseRemoval(false);
        std::vector<float> talking = FakeSpeech(kRate * 8);
        for (float& sample : talking)
        {
            sample *= 0.25f;
        }
        mic.Process(talking.data(), static_cast<int>(talking.size()));
        const size_t before = decoded.size();
        std::vector<float> shout = FakeSpeech(kRate);
        for (float& sample : shout)
        {
            sample *= 0.25f * 5.6f; // 15 dB louder
        }
        mic.Process(shout.data(), static_cast<int>(shout.size()));
        opus_decoder_destroy(decoder);
        const std::vector<float> earlier(decoded.begin() + static_cast<ptrdiff_t>(before - kRate),
                                         decoded.begin() + static_cast<ptrdiff_t>(before));
        const std::vector<float> later(decoded.begin() + static_cast<ptrdiff_t>(before), decoded.end());
        const float jump = 20.f * std::log10(Rms(later) / Rms(earlier));
        Check(jump < 9.f, "a 15 dB shout comes out as a much smaller jump", "%.1f dB", jump);
    }
    {
        MicProcessor mic([](const uint8_t*, int, bool) {});
        mic.PresetAutoGain(12.f);
        std::vector<float> quietRoom(kBlock * 2, 0.f);
        mic.Process(quietRoom.data(), static_cast<int>(quietRoom.size()));
        Check(std::fabs(mic.AutoGainDb() - 12.f) < 0.5f, "a mic starts from what it learned last time");
    }
}

// Runs an output that holds game noise at this level plus our voices at that level, for this many seconds.
void FeedAutoMix(AutoMix& aMix, float aGameDb, float aVoiceDb, float aSeconds)
{
    static std::mt19937 random(11);
    std::normal_distribution<float> noise(0.f, 1.f);
    const float game = aGameDb <= -100.f ? 0.f : std::pow(10.f, aGameDb / 20.f);
    const float voice = aVoiceDb <= -100.f ? 0.f : std::pow(10.f, aVoiceDb / 20.f);
    const int blocks = static_cast<int>(aSeconds * 100.f);
    float stereo[kBlock * 2];
    float played[kBlock];
    for (int b = 0; b < blocks; ++b)
    {
        for (int i = 0; i < kBlock; ++i)
        {
            const float ours = noise(random) * voice;
            stereo[i * 2] = ours;
            stereo[i * 2 + 1] = ours;
            played[i] = ours + noise(random) * game;
        }
        aMix.OnPlayed(played, kBlock);
        aMix.OnBlock(stereo);
    }
}

// The same, for a player whose output can't be measured.
void FeedAutoMixUnmeasured(AutoMix& aMix, float aSeconds)
{
    const std::vector<float> stereo(kBlock * 2, 0.f);
    const int blocks = static_cast<int>(aSeconds * 100.f);
    for (int b = 0; b < blocks; ++b)
    {
        aMix.OnBlock(stereo.data());
    }
}

void TestAutoMix()
{
    std::printf("voices follow the game\n");
    {
        AutoMix full;
        FeedAutoMixUnmeasured(full, 1.f);
        AutoMix low;
        low.SetGameMaster(30.f);
        FeedAutoMixUnmeasured(low, 12.f);
        const float gap = full.GainDb() - low.GainDb();
        Check(!full.Measured() && gap > 8.f && gap < 13.f, "unmeasured, voices still follow the Master Volume setting",
              "%.1f dB lower at 30", gap);
    }
    {
        // The case from the logs: the same game at Master 100 for one player and much lower for another.
        AutoMix bright;
        FeedAutoMix(bright, -18.f, -100.f, 240.f);
        AutoMix dim;
        dim.SetGameMaster(30.f);
        FeedAutoMix(dim, -30.f, -100.f, 240.f);
        const float gap = bright.GainDb() - dim.GainDb();
        std::printf("  voice gain: game at -18 dB %+.1f dB, game at -30 dB %+.1f dB\n", bright.GainDb(), dim.GainDb());
        Check(gap > 8.f && gap < 14.f, "voices track the game, so the balance holds whatever the game's volume", "%.1f dB",
              gap);
    }
    {
        AutoMix mix;
        mix.SetGameMaster(30.f);
        FeedAutoMix(mix, -30.f, -100.f, 60.f);
        const float calm = mix.GainDb();
        FeedAutoMix(mix, -12.f, -100.f, 3.f);
        const float fight = mix.GainDb();
        Check(fight > calm + 5.f, "voices rise within seconds when a fight starts", "%+.1f dB in 3 s", fight - calm);
        FeedAutoMix(mix, -8.f, -100.f, 20.f);
        Check(mix.GainDb() <= 12.f + 0.01f, "they stop at the limit, so gunfire can still win", "%+.1f dB", mix.GainDb());
        const float peak = mix.GainDb();
        FeedAutoMix(mix, -30.f, -100.f, 2.f);
        Check(peak - mix.GainDb() < 3.5f, "and they settle slowly afterwards, never a sudden drop", "%.1f dB in 2 s",
              peak - mix.GainDb());
    }
    {
        AutoMix mix;
        FeedAutoMix(mix, -40.f, -100.f, 30.f);
        const float before = mix.GainDb();
        FeedAutoMix(mix, -40.f, -8.f, 10.f);
        Check(std::fabs(mix.GainDb() - before) < 1.5f, "our own voices don't count as the game", "%.1f dB moved",
              mix.GainDb() - before);
    }
    {
        AutoMix mix;
        const float before = (FeedAutoMix(mix, -100.f, -100.f, 2.f), mix.GainDb());
        FeedAutoMix(mix, -100.f, -100.f, 120.f);
        Check(std::fabs(mix.GainDb() - before) < 0.5f, "a silent output (a menu, or a separate device) changes nothing");
    }
    {
        // What logs caught in 0.2.0: voices sinking the longer things stayed calm.
        AutoMix mix;
        FeedAutoMix(mix, -18.f, -100.f, 10.f);
        const float start = mix.GainDb();
        FeedAutoMix(mix, -40.f, -100.f, 1800.f);
        Check(start - mix.GainDb() < 3.f, "half an hour of calm play doesn't sink voices", "%.1f dB lower", start - mix.GainDb());
        Check(mix.GainDb() > 0.f, "and at Master 100 they stay above the level speech arrives at", "%+.1f dB", mix.GainDb());
    }
    {
        // Also from the logs: a burst just before a loading screen held voices up through the silence.
        AutoMix mix;
        FeedAutoMix(mix, -60.f, -100.f, 30.f);
        const float base = mix.GainDb();
        FeedAutoMix(mix, -6.f, -100.f, 2.f);
        const float burst = mix.GainDb();
        FeedAutoMix(mix, -100.f, -100.f, 60.f);
        Check(burst > base + 3.f && mix.GainDb() - base < 2.5f, "voices come back down during silence after a burst",
              "%.1f dB above where they started", mix.GainDb() - base);
    }
    {
        AutoMix mix;
        FeedAutoMix(mix, -100.f, -100.f, 1.f);
        const float base = mix.GainDb();
        mix.SetOffsetDb(4.f);
        FeedAutoMix(mix, -100.f, -100.f, 1.f);
        Check(std::fabs(mix.GainDb() - base - 4.f) < 0.5f, "the Voice level setting adds on top");
    }
}

void TestResendSchedule()
{
    std::printf("re-sending the mod list\n");
    ResendSchedule schedule;
    std::vector<double> sends;
    for (double now = 0.0; now < 120000.0; now += 2000.0)
    {
        if (schedule.Update(now, true))
        {
            sends.push_back(now);
        }
    }
    Check(!sends.empty() && sends[0] >= ResendSchedule::kFirstMs, "an ordinary connect gets time before the first re-send",
          "%.0f ms", sends.empty() ? -1.0 : sends[0]);
    Check(sends.size() >= 2 && sends[1] - sends[0] > sends[0], "the re-sends get further apart");

    ResendSchedule capped;
    int total = 0;
    for (double now = 0.0; now < 3600000.0; now += 2000.0)
    {
        total += capped.Update(now, true) ? 1 : 0;
    }
    Check(total == ResendSchedule::kMostResends, "it gives up rather than sending forever", "%.0f sends", total);

    capped.Update(3600000.0, false);
    Check(capped.Sent() == 0, "a link coming up resets it");
    capped.Update(3602000.0, true);
    Check(capped.Update(3602000.0 + ResendSchedule::kFirstMs, true), "and the next stuck player gets re-sends again");

    ResendSchedule healthy;
    bool any = false;
    for (double now = 0.0; now < 600000.0; now += 2000.0)
    {
        any = any || healthy.Update(now, false);
    }
    Check(!any, "with everyone linked it never sends");
}

void TestSignalQueue()
{
    std::printf("setup messages\n");
    const auto dir = std::filesystem::temp_directory_path() / "nightcoop-voice-test";
    Settings settings;
    settings.Load(dir / "queue.ini");
    Engine engine(settings, false);
    engine.SessionStart(1);
    engine.LinkSignal(5, SignalDescription, 1, "five-a");
    engine.LinkSignal(9, SignalDescription, 1, "nine-a");
    engine.LinkSignal(5, SignalCandidate, 1, "five-b");
    engine.LinkSignal(9, SignalCandidate, 1, "nine-b");

    std::vector<std::string> sentToNine;
    int triedFive = 0;
    const auto attempt = [&](PeerId aPeer, const std::vector<uint8_t>& aMessage) {
        if (aPeer == 5)
        {
            ++triedFive;
            return false; // their mod list hasn't registered here
        }
        sentToNine.emplace_back(aMessage.begin() + 5, aMessage.end());
        return true;
    };
    engine.DrainSignals(attempt);
    Check(sentToNine.size() == 2 && sentToNine[0] == "nine-a" && sentToNine[1] == "nine-b",
          "a player we can't reach doesn't hold up another");
    Check(triedFive == 1, "their later messages wait behind the first, so they can't overtake it");

    std::vector<std::string> sentToFive;
    engine.DrainSignals([&](PeerId, const std::vector<uint8_t>& aMessage) {
        sentToFive.emplace_back(aMessage.begin() + 5, aMessage.end());
        return true;
    });
    Check(sentToFive.size() == 2 && sentToFive[0] == "five-a" && sentToFive[1] == "five-b",
          "once reachable they get everything, in order");

    for (int i = 0; i < 2000; ++i)
    {
        engine.LinkSignal(5, SignalCandidate, 1, "x");
    }
    int queued = 0;
    engine.DrainSignals([&](PeerId, const std::vector<uint8_t>&) {
        ++queued;
        return true;
    });
    Check(queued <= 512, "an unreachable player can't grow the queue forever", "%.0f kept", queued);

    engine.AddPeer(5, "Player 0");
    Sleep(300);
    engine.SetPeerName(5, "Bossun");
    Sleep(300);
    const auto views = engine.Peers();
    Check(views.size() == 1 && views[0].name == "Bossun", "a nickname that arrives late replaces Player 0");

    engine.AddPeer(5, "Bossun");
    Sleep(300);
    Check(engine.Peers().size() == 1, "adding a known player again changes nothing");
}

void TestLinks()
{
    std::printf("direct links (real ICE between two engines on this PC)\n");
    const auto dir = std::filesystem::temp_directory_path() / "nightcoop-voice-test";
    Settings settingsA;
    Settings settingsB;
    settingsA.Load(dir / "a.ini");
    settingsB.Load(dir / "b.ini");

    Engine a(settingsA, false);
    Engine b(settingsB, false);
    a.SessionStart(0);
    b.SessionStart(7);

    VoiceKey key;
    RandomBytes(key.data(), key.size());
    a.SetKey(key.data(), key.size());
    b.SetKey(key.data(), key.size());
    a.AddPeer(7, "Bee");
    b.AddPeer(0, "Ay");

    const double start = NowMs();
    bool linked = false;
    while (NowMs() - start < 20000.0)
    {
        Pump(a, 0, b);
        Pump(b, 7, a);
        const auto peersA = a.Peers();
        const auto peersB = b.Peers();
        if (!peersA.empty() && !peersB.empty() && peersA[0].link == PeerLink::Linked && peersB[0].link == PeerLink::Linked)
        {
            linked = true;
            break;
        }
        Sleep(5);
    }
    Check(linked, "the two sides find each other", "%.0f ms", NowMs() - start);
    if (!linked)
    {
        return;
    }

    // Everyone stands close, and B listens for what A says.
    a.SetListener({0.f, 0.f, 0.f}, {0.f, 1.f, 0.f}, {1.f, 0.f, 0.f});
    b.SetListener({0.f, 2.f, 0.f}, {0.f, -1.f, 0.f}, {-1.f, 0.f, 0.f});

    settingsA.Set("gate", "0");
    a.ApplySettings();

    const std::vector<float> speech = FakeSpeech(kRate);
    std::vector<float> heard;
    float block[kBlock * 2];
    int sent = 0;
    const double talkStart = NowMs();
    double firstHeardMs = -1.0;
    while (sent + kBlock <= static_cast<int>(speech.size()))
    {
        a.SetPeerSpatial(7, {0.f, 2.f, 0.f}, {}, CabinNone);
        b.SetPeerSpatial(0, {0.f, 0.f, 0.f}, {}, CabinNone);
        a.InjectMic(speech.data() + sent, kBlock);
        sent += kBlock;
        b.GetMixer().Render(block);
        for (int i = 0; i < kBlock; ++i)
        {
            heard.push_back(block[i * 2]);
            if (firstHeardMs < 0.0 && std::fabs(block[i * 2]) > 0.002f)
            {
                firstHeardMs = NowMs() - talkStart;
            }
        }
        Sleep(10);
    }
    Check(Rms(heard) > 0.002f, "what A says comes out of B's mixer", "rms %.4f", Rms(heard));
    Check(firstHeardMs >= 0.0, "first sound arrives", "%.0f ms", firstHeardMs);

    // Move out of range: A stops sending nearby voice to B.
    const auto moveApart = [&] {
        a.SetPeerSpatial(7, {0.f, 200.f, 0.f}, {}, CabinNone);
        b.SetPeerSpatial(0, {0.f, -200.f, 0.f}, {}, CabinNone);
    };
    std::vector<float> distant;
    moveApart();
    sent = 0;
    while (sent + kBlock <= static_cast<int>(speech.size()))
    {
        moveApart();
        a.InjectMic(speech.data() + sent, kBlock);
        sent += kBlock;
        b.GetMixer().Render(block);
        if (sent > kRate / 2) // past what was already queued
        {
            for (int i = 0; i < kBlock; ++i)
            {
                distant.push_back(block[i * 2]);
            }
        }
        Sleep(10);
    }
    Check(Rms(distant) < 0.002f, "200 m apart with the radio mic off, nothing is heard", "rms %.5f", Rms(distant));

    // Same distance, holding the radio key.
    a.RadioKeyDown();
    std::vector<float> radio;
    sent = 0;
    while (sent + kBlock <= static_cast<int>(speech.size()))
    {
        moveApart();
        a.InjectMic(speech.data() + sent, kBlock);
        sent += kBlock;
        b.GetMixer().Render(block);
        for (int i = 0; i < kBlock; ++i)
        {
            radio.push_back(block[i * 2]);
        }
        Sleep(10);
    }
    Check(Rms(radio) > 0.005f, "200 m apart holding the radio key, B hears A on it", "rms %.4f", Rms(radio));

    // Close by, a held key or combat still puts A on B's radio, and letting go takes A off it.
    const auto standClose = [&] {
        a.SetPeerSpatial(7, {0.f, 2.f, 0.f}, {}, CabinNone);
        b.SetPeerSpatial(0, {0.f, 0.f, 0.f}, {}, CabinNone);
    };
    const auto talkCloseOnRadio = [&] {
        bool onRadio = false;
        sent = 0;
        while (sent + kBlock <= static_cast<int>(speech.size()))
        {
            standClose();
            a.InjectMic(speech.data() + sent, kBlock);
            sent += kBlock;
            b.GetMixer().Render(block);
            if (sent > kRate / 2) // past the presence's way over and the cut's fade
            {
                const auto views = b.Peers();
                onRadio = onRadio || (!views.empty() && views[0].talkingRadio);
            }
            Sleep(10);
        }
        return onRadio;
    };
    for (int i = 0; i < 50; ++i) // what's queued from afar plays out, and its lit radio goes dark
    {
        standClose();
        b.GetMixer().Render(block);
        Sleep(10);
    }
    Check(talkCloseOnRadio(), "holding the key 2 m away, B hears A on the radio too");
    a.RadioKeyUp();
    for (int i = 0; i < 50; ++i) // the tail and what's queued play out, and the lit radio goes dark
    {
        standClose();
        b.GetMixer().Render(block);
        Sleep(10);
    }
    Check(!talkCloseOnRadio(), "once A lets go, B hears A only in the air");
    a.SetInCombat(true);
    Check(talkCloseOnRadio(), "in combat, B hears A on the radio without the key");
    a.SetInCombat(false);

    // A sits in a shut car 10 m from B, who isn't heard past the cabin's 5 m, until A winds the driver's window down: A's
    // presence tells B at once, so both send and hear through it.
    {
        const CarFrame carFrame; // at the origin, facing +y
        const Vec3 bAt{-10.f, 0.2f, 1.f};
        DescribeHozuki(a, Engine::kOurCar, 42);
        DescribeHozuki(b, 0, 42);
        a.SetListener(kHozukiDriverHead, {0.f, 1.f, 0.f}, {1.f, 0.f, 0.f});
        b.SetListener(bAt, {1.f, 0.f, 0.f}, {0.f, -1.f, 0.f});
        const auto placeInCar = [&](const CarStates& aStates) {
            a.SetOurCar(42, carFrame, kHozukiDriverHead, aStates);
            a.SetPeerSpatial(7, bAt, {}, CabinSeparated);
            b.SetPeerCar(0, 42, carFrame);
            b.SetPeerSpatial(0, kHozukiDriverHead, {}, CabinSeparated);
        };
        const auto talkFromCar = [&](const CarStates& aStates) {
            for (int i = 0; i < 150; ++i) // getting in takes a second to muffle, and what's queued plays out
            {
                placeInCar(aStates);
                b.GetMixer().Render(block);
                Sleep(10);
            }
            std::vector<float> got;
            sent = 0;
            while (sent + kBlock <= static_cast<int>(speech.size()))
            {
                placeInCar(aStates);
                a.InjectMic(speech.data() + sent, kBlock);
                sent += kBlock;
                b.GetMixer().Render(block);
                if (sent > kRate / 2) // past the presence's way over and what was queued
                {
                    for (int i = 0; i < kBlock; ++i)
                    {
                        got.push_back(block[i * 2]);
                    }
                }
                Sleep(10);
            }
            return Rms(got);
        };
        const float shut = talkFromCar({});
        const float open = talkFromCar(WindowDown(0));
        a.SetOurCar(0, {}, {}, {});
        b.SetPeerCar(0, 0, {});
        a.SetListener({0.f, 0.f, 0.f}, {0.f, 1.f, 0.f}, {1.f, 0.f, 0.f});
        b.SetListener({0.f, 2.f, 0.f}, {0.f, -1.f, 0.f}, {-1.f, 0.f, 0.f});
        Check(shut < 0.002f, "A in a shut car 10 m away isn't heard", "rms %.5f", shut);
        Check(open > 0.002f, "with A's window wound down, B hears A through it", "rms %.4f", open);
    }

    Sleep(2500); // presence comes once a second
    Pump(a, 0, b);
    Pump(b, 7, a);
    const auto views = b.Peers();
    Check(!views.empty() && views[0].pingMs >= 0 && views[0].pingMs < 100, "the ping is measured",
          "%.0f ms", views.empty() ? -1.0 : views[0].pingMs);
    a.ToggleMute();
    Sleep(1500);
    const auto mutedViews = b.Peers();
    Check(!mutedViews.empty() && mutedViews[0].muted, "B sees that A muted");
    a.ToggleMute();

    // A tamperer without the key can't be heard: B swaps to a wrong key and hears nothing more.
    VoiceKey wrong = key;
    wrong[5] ^= 0x40;
    b.SetKey(wrong.data(), wrong.size());
    Sleep(200);
    for (int i = 0; i < 40; ++i)
    {
        b.GetMixer().Render(block); // plays out what was queued before the swap
    }
    a.RadioKeyDown();
    std::vector<float> locked;
    sent = 0;
    while (sent + kBlock <= static_cast<int>(speech.size()))
    {
        moveApart();
        a.InjectMic(speech.data() + sent, kBlock);
        sent += kBlock;
        b.GetMixer().Render(block);
        for (int i = 0; i < kBlock; ++i)
        {
            locked.push_back(block[i * 2]);
        }
        Sleep(10);
    }
    a.RadioKeyUp();
    Check(Rms(locked) < 0.002f, "packets under another key are dropped");

    a.RemovePeer(7);
    b.SessionEnd();
    Sleep(300);
    Check(a.Peers().empty() && b.Peers().empty(), "leaving cleans up");
}

// ---- the Relay

// How many audio frames a Relay message carries: a 4-byte send time, then a 2-byte size and a sealed packet each.
int AudioFramesIn(const uint8_t* aData, size_t aSize)
{
    int frames = 0;
    size_t at = 4;
    while (at + 2 <= aSize)
    {
        const size_t size = static_cast<size_t>(aData[at]) | static_cast<size_t>(aData[at + 1]) << 8;
        at += 2;
        if (size > aSize - at)
        {
            break;
        }
        frames += size > 0 && aData[at] == PacketAudio ? 1 : 0;
        at += size;
    }
    return frames;
}

// NightCoop's channel between test engines. A message is in flight for a while and arrives only when the test's game
// thread delivers it. Each sender is held to NightCoop's rate per mod and direction, as its send() answers it.
class FakeNightCoop
{
public:
    struct Sender
    {
        bool started = false;
        double messages = 0.0;
        double bytes = 0.0;
        double refilledMs = 0.0;
        std::deque<std::pair<double, size_t>> lastSecond;
        int sent = 0;
        int refused = 0;
        int mostFrames = 0;
        size_t mostMessagesInASecond = 0;
        size_t mostBytesInASecond = 0;
    };

    double delayMs = 60.0;
    double messagesPerSecond = 120.0; // NCSDK_RATE_MESSAGES_PER_S
    double bytesPerSecond = 32768.0;  // NCSDK_RATE_BYTES_PER_S
    bool hold = false;                // a loading screen: nothing arrives until it's over
    bool deliverTwice = false;

    RelaySend Send(PeerId aFrom, PeerId aTo, const uint8_t* aData, size_t aSize)
    {
        const double now = NowMs();
        Sender& sender = m_senders[aFrom];
        if (!sender.started)
        {
            sender.started = true;
            sender.messages = messagesPerSecond;
            sender.bytes = bytesPerSecond;
            sender.refilledMs = now;
        }
        // Bursts of up to a second's worth, which is 4 times the rate for a quarter of a second.
        const double seconds = (now - sender.refilledMs) / 1000.0;
        sender.refilledMs = now;
        sender.messages = std::min(messagesPerSecond, sender.messages + seconds * messagesPerSecond);
        sender.bytes = std::min(bytesPerSecond, sender.bytes + seconds * bytesPerSecond);
        if (aSize > kRelayMaxMessage)
        {
            ++sender.refused;
            return RelaySend::Refused;
        }
        if (sender.messages < 1.0 || sender.bytes < static_cast<double>(aSize))
        {
            ++sender.refused;
            return RelaySend::Limit;
        }
        sender.messages -= 1.0;
        sender.bytes -= static_cast<double>(aSize);
        ++sender.sent;

        sender.lastSecond.emplace_back(now, aSize);
        while (now - sender.lastSecond.front().first >= 1000.0)
        {
            sender.lastSecond.pop_front();
        }
        size_t bytes = 0;
        for (const auto& entry : sender.lastSecond)
        {
            bytes += entry.second;
        }
        sender.mostMessagesInASecond = std::max(sender.mostMessagesInASecond, sender.lastSecond.size());
        sender.mostBytesInASecond = std::max(sender.mostBytesInASecond, bytes);
        sender.mostFrames = std::max(sender.mostFrames, AudioFramesIn(aData, aSize));

        m_flight.push_back({now + delayMs, aFrom, aTo, std::vector<uint8_t>(aData, aData + aSize)});
        return RelaySend::Sent;
    }

    // The game thread of every engine: what has arrived goes to its engine.
    void Deliver(const std::vector<std::pair<PeerId, Engine*>>& aEngines)
    {
        if (hold)
        {
            return;
        }
        const double now = NowMs();
        while (!m_flight.empty() && m_flight.front().dueMs <= now)
        {
            const InFlight message = std::move(m_flight.front());
            m_flight.pop_front();
            for (const auto& [id, engine] : aEngines)
            {
                if (id == message.to)
                {
                    for (int i = 0; i < (deliverTwice ? 2 : 1); ++i)
                    {
                        engine->OnRelay(message.from, message.data.data(), message.data.size());
                    }
                }
            }
        }
    }

    Sender& From(PeerId aPeer)
    {
        return m_senders[aPeer];
    }

private:
    struct InFlight
    {
        double dueMs = 0.0;
        PeerId from = 0;
        PeerId to = 0;
        std::vector<uint8_t> data;
    };
    std::map<PeerId, Sender> m_senders;
    std::deque<InFlight> m_flight;
};

// Setup messages between two engines. Blocked, they're lost, as if no direct link could ever form. Those for partners
// with no engine behind them are lost too.
int PumpSignals(Engine& aFrom, PeerId aFromId, Engine& aTo, PeerId aToId, bool aBlocked)
{
    int count = 0;
    aFrom.DrainSignals([&](PeerId aPeer, const std::vector<uint8_t>& aMessage) {
        ++count;
        if (!aBlocked && aPeer == aToId)
        {
            aTo.OnSignal(aFromId, aMessage.data(), aMessage.size());
        }
        return true;
    });
    return count;
}

// Two engines standing 2 m apart, with real direct links and a fake NightCoop channel, run 10 ms at a time. A can
// also have partners with no engine behind them, who only receive.
struct RelayRig
{
    RelayRig(const char* aName, PeerId aIdA, PeerId aIdB, bool aAlwaysA = false, bool aAlwaysB = false)
        : idA(aIdA)
        , idB(aIdB)
    {
        const auto dir = std::filesystem::temp_directory_path() / "nightcoop-voice-test";
        const std::string name(aName);
        settingsA.Load(dir / ("relay-" + name + "-a.ini"));
        settingsB.Load(dir / ("relay-" + name + "-b.ini"));
        for (Settings* settings : {&settingsA, &settingsB})
        {
            settings->Set("gate", "0");
            settings->Set("muted", "0");
        }
        settingsA.Set("relay", aAlwaysA ? "always" : "needed");
        settingsB.Set("relay", aAlwaysB ? "always" : "needed");
        a = std::make_unique<Engine>(settingsA, false);
        b = std::make_unique<Engine>(settingsB, false);
        a->SessionStart(idA);
        b->SessionStart(idB);
        VoiceKey key;
        RandomBytes(key.data(), key.size());
        a->SetKey(key.data(), key.size());
        b->SetKey(key.data(), key.size());
        a->AddPeer(idB, "Bee");
        b->AddPeer(idA, "Ay");
        a->SetListener({0.f, 0.f, 0.f}, {0.f, 1.f, 0.f}, {1.f, 0.f, 0.f});
        b->SetListener({0.f, 2.f, 0.f}, {0.f, -1.f, 0.f}, {-1.f, 0.f, 0.f});
    }

    void AddListenerOnlyPartner(PeerId aPeer)
    {
        a->AddPeer(aPeer, "Partner " + std::to_string(aPeer));
        onlyListening.push_back(aPeer);
    }

    void SetRelay(Settings& aSettings, Engine& aEngine, bool aAlways)
    {
        aSettings.Set("relay", aAlways ? "always" : "needed");
        aEngine.ApplySettings();
    }

    void Step(bool aTalkA, bool aTalkB)
    {
        a->SetPeerSpatial(idB, {0.f, 2.f, 0.f}, {}, CabinNone);
        b->SetPeerSpatial(idA, {0.f, 0.f, 0.f}, {}, CabinNone);
        for (const PeerId peer : onlyListening)
        {
            a->SetPeerSpatial(peer, {1.f, 1.f, 0.f}, {}, CabinNone);
        }
        signalsFromA += PumpSignals(*a, idA, *b, idB, blockDirect);
        signalsFromB += PumpSignals(*b, idB, *a, idA, blockDirect);

        // The audio threads, at real speed in 10 ms blocks however long a step took: Sleep is coarse on Windows.
        if (audioStartMs < 0.0)
        {
            audioStartMs = NowMs();
        }
        const int64_t due = static_cast<int64_t>((NowMs() - audioStartMs) / 10.0);
        float block[kBlock * 2];
        for (; blocksDone < due; ++blocksDone)
        {
            if (aTalkA)
            {
                a->InjectMic(speech.data() + speechAt, kBlock);
                samplesFromA += kBlock;
            }
            if (aTalkB)
            {
                b->InjectMic(speech.data() + speechAt, kBlock);
            }
            speechAt = (speechAt + kBlock) % speech.size();
            b->GetMixer().Render(block);
            for (int i = 0; i < kBlock; ++i)
            {
                heardByB.push_back(block[i * 2]);
            }
            a->GetMixer().Render(block);
            for (int i = 0; i < kBlock; ++i)
            {
                heardByA.push_back(block[i * 2]);
            }
        }

        // Each engine's game thread, one frame a step.
        if (!stallA)
        {
            const double start = NowMs();
            a->DrainRelay([&](PeerId aTo, const uint8_t* aData, size_t aSize) { return channel.Send(idA, aTo, aData, aSize); });
            longestDrainMs = std::max(longestDrainMs, NowMs() - start);
        }
        b->DrainRelay([&](PeerId aTo, const uint8_t* aData, size_t aSize) { return channel.Send(idB, aTo, aData, aSize); });
        channel.Deliver({{idA, a.get()}, {idB, b.get()}});
        Sleep(5);
    }

    void Run(double aMs, bool aTalkA, bool aTalkB)
    {
        const double until = NowMs() + aMs;
        while (NowMs() < until)
        {
            Step(aTalkA, aTalkB);
        }
    }

    // Steps until both see a direct link, or the time is up.
    bool RunUntilLinked(double aMs, bool aTalkA)
    {
        const double until = NowMs() + aMs;
        while (NowMs() < until)
        {
            if (ViewOf(*a, idB).link == PeerLink::Linked && ViewOf(*b, idA).link == PeerLink::Linked)
            {
                return true;
            }
            Step(aTalkA, false);
        }
        return false;
    }

    static PeerView ViewOf(const Engine& aEngine, PeerId aPeer)
    {
        for (const PeerView& view : aEngine.Peers())
        {
            if (view.id == aPeer)
            {
                return view;
            }
        }
        return {};
    }

    static float RmsOfLast(const std::vector<float>& aHeard, double aSeconds)
    {
        const size_t count = std::min(aHeard.size(), static_cast<size_t>(aSeconds * kRate));
        return Rms(std::vector<float>(aHeard.end() - static_cast<ptrdiff_t>(count), aHeard.end()));
    }

    int FramesFromA() const
    {
        return samplesFromA / kFrame;
    }

    Settings settingsA;
    Settings settingsB;
    std::unique_ptr<Engine> a;
    std::unique_ptr<Engine> b;
    PeerId idA;
    PeerId idB;
    std::vector<PeerId> onlyListening;
    FakeNightCoop channel;
    bool blockDirect = false;
    bool stallA = false; // A's game thread stops, as in a load
    int signalsFromA = 0;
    int signalsFromB = 0;
    int samplesFromA = 0;
    double audioStartMs = -1.0;
    int64_t blocksDone = 0;
    double longestDrainMs = 0.0;
    std::vector<float> speech = FakeSpeech(kRate);
    size_t speechAt = 0;
    std::vector<float> heardByA;
    std::vector<float> heardByB;
};

void TestRelayWithoutDirect()
{
    std::printf("the Relay, with no direct link (a fake NightCoop channel, 60 ms each way)\n");
    RelayRig rig("blocked", 0, 7);
    rig.blockDirect = true;
    rig.Run(1500.0, false, false); // presence, each way
    rig.Run(3000.0, true, false);

    const PeerView seenByB = RelayRig::ViewOf(*rig.b, 0);
    const PeerView seenByA = RelayRig::ViewOf(*rig.a, 7);
    const PathStats heard = rig.b->Stats(0);
    Check(RelayRig::RmsOfLast(rig.heardByB, 2.0) > 0.002f, "B hears A over the Relay", "rms %.4f",
          RelayRig::RmsOfLast(rig.heardByB, 2.0));
    Check(heard.heardRelay > 100 && heard.heardDirect == 0, "every frame came over the Relay", "%.0f frames",
          heard.heardRelay);
    Check(seenByB.relay && seenByB.link != PeerLink::Linked && seenByA.relay,
          "both show the Relay, not a direct link");
    Check(rig.channel.From(0).mostFrames == 2, "two 20 ms frames to a message", "%.0f",
          rig.channel.From(0).mostFrames);
    Check(rig.channel.From(0).mostMessagesInASecond <= 30, "about 25 messages a second, with presence",
          "%.0f in the busiest second", static_cast<double>(rig.channel.From(0).mostMessagesInASecond));
    Check(seenByB.pingMs >= 120 && seenByB.pingMs < 400, "the ping is the Relay's round trip", "%.0f ms",
          seenByB.pingMs);

    rig.a->ToggleMute();
    rig.Run(1500.0, false, false);
    Check(RelayRig::ViewOf(*rig.b, 0).muted, "B sees that A muted, over the Relay");
    rig.a->ToggleMute();

    // NightCoop shouldn't deliver a message twice, but if it did, each frame still plays once.
    const uint32_t duplicatesBefore = rig.b->Stats(0).duplicates;
    rig.channel.deliverTwice = true;
    rig.Run(1000.0, true, false);
    rig.channel.deliverTwice = false;
    Check(rig.b->Stats(0).duplicates - duplicatesBefore > 20, "a frame that comes twice plays once",
          "%.0f copies dropped", rig.b->Stats(0).duplicates - duplicatesBefore);

    // A load on B's side: messages pile up and then come all at once.
    const PathStats beforeHold = rig.b->Stats(0);
    rig.channel.hold = true;
    rig.Run(2000.0, true, false);
    rig.channel.hold = false;
    rig.Run(1500.0, true, false);
    const PathStats afterHold = rig.b->Stats(0);
    Check(afterHold.stale - beforeHold.stale > 50, "a backlog after a load is dropped, not played late",
          "%.0f frames dropped", afterHold.stale - beforeHold.stale);
    Check(afterHold.heardRelay - beforeHold.heardRelay > 40 && RelayRig::RmsOfLast(rig.heardByB, 1.0) > 0.002f,
          "and voice goes on after it", "%.0f frames", afterHold.heardRelay - beforeHold.heardRelay);

    // A load on A's side: its game thread stops, so the Relay's frames wait.
    const uint32_t oldBefore = rig.a->Stats(7).tooOld;
    rig.stallA = true;
    rig.Run(1000.0, true, false);
    rig.stallA = false;
    rig.Run(500.0, true, false);
    Check(rig.a->Stats(7).tooOld - oldBefore > 30, "frames that waited through a stall are dropped, not sent late",
          "%.0f dropped", rig.a->Stats(7).tooOld - oldBefore);
    Check(rig.longestDrainMs < 5.0, "the game thread's drain never waits", "%.2f ms at most", rig.longestDrainMs);
}

void TestRelayAlways()
{
    std::printf("the Relay on Always\n");
    // A is on Always, and B is the side that offers direct links, so this also shows A ignoring offers.
    RelayRig rig("always", 7, 0, true, false);
    rig.Run(3000.0, false, false);
    Check(rig.signalsFromA == 0, "Always makes no direct link: not one setup message", "%.0f sent", rig.signalsFromA);
    Check(RelayRig::ViewOf(*rig.b, 7).relay && RelayRig::ViewOf(*rig.a, 0).relay &&
              RelayRig::ViewOf(*rig.b, 7).link != PeerLink::Linked && RelayRig::ViewOf(*rig.a, 0).link != PeerLink::Linked,
          "both sides are on the Relay");

    rig.Run(2500.0, true, false);
    rig.Run(2500.0, false, true);
    const PathStats atB = rig.b->Stats(7);
    const PathStats atA = rig.a->Stats(0);
    Check(atB.heardRelay > 80 && atB.heardDirect == 0, "the Always side's voice reaches the other over the Relay",
          "%.0f frames", atB.heardRelay);
    Check(atA.heardRelay > 80 && atA.heardDirect == 0, "and the other side's reaches it the same way", "%.0f frames",
          atA.heardRelay);

    // The other side on Always instead.
    rig.SetRelay(rig.settingsA, *rig.a, false);
    rig.SetRelay(rig.settingsB, *rig.b, true);
    rig.Run(1500.0, false, false);
    const int signalsBefore = rig.signalsFromA + rig.signalsFromB;
    const PathStats beforeSwap = rig.b->Stats(7);
    rig.Run(2500.0, true, false);
    Check(rig.signalsFromA + rig.signalsFromB == signalsBefore && RelayRig::ViewOf(*rig.a, 0).relay &&
              rig.b->Stats(7).heardRelay - beforeSwap.heardRelay > 80 && rig.b->Stats(7).heardDirect == 0,
          "with the other side on Always, still the Relay both ways and no direct link");

    rig.SetRelay(rig.settingsB, *rig.b, false);
    const double start = NowMs();
    const bool linked = rig.RunUntilLinked(10000.0, false);
    Check(linked, "with both back on When needed, the direct link comes up", "%.0f ms", NowMs() - start);
}

void TestRelaySwitches()
{
    std::printf("switching between direct and the Relay while talking\n");
    RelayRig rig("switch", 0, 7);
    if (!rig.RunUntilLinked(20000.0, false))
    {
        Check(false, "the two sides find each other directly first");
        return;
    }
    rig.Run(1000.0, false, false);
    rig.samplesFromA = 0;
    const PathStats before = rig.b->Stats(0);

    rig.Run(1500.0, true, false);
    const PathStats direct = rig.b->Stats(0);
    rig.SetRelay(rig.settingsA, *rig.a, true);
    rig.Run(2500.0, true, false);
    const PathStats relay = rig.b->Stats(0);
    Check(RelayRig::RmsOfLast(rig.heardByB, 1.5) > 0.002f && RelayRig::ViewOf(*rig.b, 0).relay,
          "set to Always mid-sentence, the voice carries on over the Relay");
    rig.SetRelay(rig.settingsA, *rig.a, false);
    const bool back = rig.RunUntilLinked(10000.0, true);
    rig.Run(1500.0, true, false);
    const PathStats after = rig.b->Stats(0);

    const uint32_t heardDirect = after.heardDirect - before.heardDirect;
    const uint32_t heardRelay = after.heardRelay - before.heardRelay;
    // A talked without a pause, so its voice gate opened once, and the mic sent the 20 ms before that first.
    const uint32_t made = static_cast<uint32_t>(rig.FramesFromA()) + 1;
    Check(direct.heardDirect > before.heardDirect && relay.heardRelay > direct.heardRelay &&
              after.heardDirect > relay.heardDirect,
          "direct, then the Relay, then direct again", "%.0f frames over the Relay", heardRelay);
    Check(back && RelayRig::ViewOf(*rig.a, 7).link == PeerLink::Linked && !RelayRig::ViewOf(*rig.a, 7).relay &&
              RelayRig::RmsOfLast(rig.heardByB, 1.0) > 0.002f,
          "back on When needed, voice returns to the direct link");
    Check(after.duplicates == before.duplicates, "no frame came twice across the switches");
    std::printf("    A made %u frames; B took %u direct and %u over the Relay\n", made, heardDirect, heardRelay);
    Check(heardDirect + heardRelay <= made && heardDirect + heardRelay >= made * 85 / 100,
          "every frame A made reached B once, give or take a few at a switch", "%.1f%%",
          100.0 * (heardDirect + heardRelay) / std::max(made, 1u));
}

void TestRelayRate()
{
    std::printf("the Relay within NightCoop's rate limit\n");
    {
        RelayRig rig("partners", 0, 7);
        rig.blockDirect = true;
        for (PeerId peer = 1; peer <= 4; ++peer)
        {
            rig.AddListenerOnlyPartner(peer);
        }
        rig.Run(1500.0, false, false);
        rig.Run(3000.0, true, false);
        FakeNightCoop::Sender& fromA = rig.channel.From(0);
        Check(fromA.mostFrames == 3, "with five partners on the Relay, three frames to a message", "%.0f",
              fromA.mostFrames);
        Check(fromA.mostMessagesInASecond <= 120, "within 120 messages a second", "%.0f in the busiest second",
              static_cast<double>(fromA.mostMessagesInASecond));
        Check(fromA.refused == 0, "and within 32768 bytes a second", "%.0f bytes in the busiest second",
              static_cast<double>(fromA.mostBytesInASecond));
        Check(RelayRig::RmsOfLast(rig.heardByB, 2.0) > 0.002f, "B hears A");
    }
    {
        RelayRig rig("tight", 0, 7);
        rig.blockDirect = true;
        rig.channel.messagesPerSecond = 15.0; // far under what two frames a message needs
        rig.Run(1500.0, false, false);
        rig.Run(3500.0, true, false);
        FakeNightCoop::Sender& fromA = rig.channel.From(0);
        const int refusedThen = fromA.refused;
        const uint32_t heardThen = rig.b->Stats(0).heardRelay;
        rig.Run(2000.0, true, false);
        Check(refusedThen > 0 && rig.a->Stats(7).refusedLimit > 0, "over a tight limit, NightCoop refuses some",
              "%.0f refused", refusedThen);
        Check(fromA.mostFrames == 4, "the mod packs more frames to a message", "%.0f at most", fromA.mostFrames);
        Check(fromA.refused == refusedThen, "and then fits under the limit");
        Check(rig.b->Stats(0).heardRelay - heardThen > 60 && RelayRig::RmsOfLast(rig.heardByB, 1.5) > 0.002f,
              "voice still gets through", "%.0f frames in 2 s", rig.b->Stats(0).heardRelay - heardThen);
        Check(rig.longestDrainMs < 5.0, "it never waits for NightCoop", "%.2f ms at most", rig.longestDrainMs);
    }
}

void TestDevices()
{
    std::printf("audio devices\n");
    const auto microphones = ListDevices(true);
    const auto outputs = ListDevices(false);
    std::printf("  %zu microphone(s), %zu output(s)\n", microphones.size(), outputs.size());
    for (const auto& device : microphones)
    {
        std::printf("    mic: %s\n", device.name.c_str());
    }
    for (const auto& device : outputs)
    {
        std::printf("    out: %s\n", device.name.c_str());
    }

    ComThread com;
    {
        RenderStream output;
        const bool opened = output.Open("");
        Check(opened, "the default output opens");
        if (opened)
        {
            // Silence only: nothing is audible during the test.
            std::vector<float> quiet(kBlock * 2, 0.f);
            bool wrote = true;
            const double until = NowMs() + 300.0;
            while (NowMs() < until && wrote)
            {
                int wanted = output.Wanted();
                while (wanted >= kBlock && wrote)
                {
                    wrote = output.Write(quiet.data(), kBlock);
                    wanted -= kBlock;
                }
                output.Wait(10);
            }
            Check(wrote, "the output takes audio");
        }
    }
    if (!microphones.empty())
    {
        CaptureStream mic;
        const bool opened = mic.Open("", false);
        Check(opened, "the default microphone opens");
        if (opened)
        {
            std::vector<float> samples;
            const double until = NowMs() + 500.0;
            bool read = true;
            while (NowMs() < until && read)
            {
                read = mic.Read(samples, 20);
            }
            Check(read && samples.size() > kRate / 4, "the microphone delivers 48 kHz samples", "%.0f in 0.5 s",
                  static_cast<double>(samples.size()));
            samples.clear(); // never kept
        }
    }
    CaptureStream loopback;
    Check(loopback.Open("", true), "the output loopback opens");
}

// ---- the radio headset (RECORD.md, 2026-11-07)

float SignalDb(const float* aSamples, size_t aCount, size_t aStride)
{
    double sum = 0.0;
    size_t count = 0;
    for (size_t i = 0; i < aCount; i += aStride)
    {
        sum += static_cast<double>(aSamples[i]) * aSamples[i];
        ++count;
    }
    return 10.f * std::log10(static_cast<float>(std::max(sum / std::max<size_t>(count, 1), 1e-14)));
}

// The left ear of interleaved stereo, between two frames, split at 250 Hz and 2 kHz the way the recordings were measured.
void BandsDb(const std::vector<float>& aStereo, size_t aFrom, size_t aTo, float& aWhole, float& aBass, float& aTreble)
{
    const auto pole = [](float aHz) { return 1.f - std::exp(-2.f * kPi * aHz / kRate); };
    const float lowA = pole(250.f);
    const float highA = pole(2000.f);
    float low1 = 0.f, low2 = 0.f, high1 = 0.f, high2 = 0.f;
    double whole = 0.0, bass = 0.0, treble = 0.0;
    for (size_t frame = 0; frame < aTo; ++frame)
    {
        const float x = aStereo[frame * 2];
        low1 += lowA * (x - low1);
        low2 += lowA * (low1 - low2);
        high1 += highA * (x - high1);
        high2 += highA * (high1 - high2);
        if (frame >= aFrom)
        {
            whole += static_cast<double>(x) * x;
            bass += static_cast<double>(low2) * low2;
            treble += static_cast<double>(x - high2) * (x - high2);
        }
    }
    const double count = static_cast<double>(std::max<size_t>(aTo - aFrom, 1));
    aWhole = 10.f * std::log10(static_cast<float>(std::max(whole / count, 1e-14)));
    aBass = 10.f * std::log10(static_cast<float>(std::max(bass / count, 1e-14)));
    aTreble = 10.f * std::log10(static_cast<float>(std::max(treble / count, 1e-14)));
}

void TestHeadsetLink()
{
    std::printf("the link to the Headset mod\n");
    SetHeadsetApiForTest(nullptr);
    float left[4] = {0.5f, 0.5f, 0.5f, 0.5f};
    float right[4] = {0.5f, 0.5f, 0.5f, 0.5f};
    ProcessVoicesThroughHeadset(left, right, 4);
    Check(left[0] == 0.5f && right[3] == 0.5f, "without the mod, voices pass untouched");
    Check(!HeadsetLinked(), "and voice knows it isn't there");

    HeadsetApi fake{};
    fake.version = HEADSET_API_VERSION;
    fake.EffectiveMode = []() { return 1; };
    fake.ProcessNearbyVoices = [](float* aLeft, float* aRight, int aFrames) {
        for (int i = 0; i < aFrames; ++i)
        {
            aLeft[i] *= 0.5f;
            aRight[i] *= 0.5f;
        }
    };
    SetHeadsetApiForTest(&fake);
    Check(HeadsetLinked(), "with it, voice finds it");
    ProcessVoicesThroughHeadset(left, right, 4);
    Check(left[0] == 0.25f && right[3] == 0.25f, "and nearby voices go through it");
    SetHeadsetApiForTest(nullptr);
}
} // namespace

int main(int aCount, char** aArguments)
{
    SetLogSink([](int aLevel, const char* aText) {
        if (aLevel >= LogWarn)
        {
            std::printf("    [log] %s\n", aText);
        }
    });

    const bool withDevices = !(aCount > 1 && std::strcmp(aArguments[1], "--no-devices") == 0);
    TestPackets();
    TestSpatial();
    TestJitter();
    TestMic();
    TestMicLevels();
    TestAutoMix();
    TestListenerAndFacing();
    TestEasing();
    TestRadio();
    TestMixer();
    TestRooms();
    TestWallsBetween();
    TestWaysRound();
    TestPathSound();
    TestCars();
    TestEchoes();
    TestRoomReverb();
    TestRoomInMixer();
    TestResendSchedule();
    TestSignalQueue();
    TestLinks();
    TestRelayWithoutDirect();
    TestRelayAlways();
    TestRelaySwitches();
    TestRelayRate();
    TestHeadsetLink();
    if (withDevices)
    {
        TestDevices();
    }

    std::printf("\n%s (%d failure%s)\n", g_failures == 0 ? "ALL OK" : "FAILED", g_failures, g_failures == 1 ? "" : "s");
    return g_failures == 0 ? 0 : 1;
}
