/* What other mods can ask of Headset. Find it with GetProcAddress(GetModuleHandleW(L"Headset.dll"), "Headset_GetApi"), and carry on
 * without it if the plug-in isn't there. Pin the module (GET_MODULE_HANDLE_EX_FLAG_PIN) so its code can't go away under your audio
 * thread at shutdown. */
#pragma once

#include <stdbool.h>
#include <stdint.h>

#define HEADSET_API_VERSION 2

typedef struct HeadsetApi
{
    uint32_t version;

    /* 0 Passthrough, 1 Hearing Protection, 2 Noise Cancelling: what the headset is doing now. */
    int (*EffectiveMode)(void);

    /* Other players' voices, 48 kHz stereo, heard through the headset as the world is at that moment. One audio thread only. */
    void (*ProcessNearbyVoices)(float* left, float* right, int frames);
} HeadsetApi;

typedef const HeadsetApi* (*Headset_GetApi_t)(uint32_t version);
