// A car's gaps: which windows, doors and roofs are open, and where they are, from the parts the game names and the boxes
// of their meshes in car_meshes.inc (tools/car_openings.py). No game in it, so the test program can build cars.
#pragma once

#include "audio/spatial.hpp"
#include "core/common.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace nv
{
// What's open on a car, as the game of the player sitting in it says. Each player reports their own car's in presence.
struct CarStates
{
    uint32_t glassGone = 0;  // bit i: the car record's glass i is shot out (its part is switched off)
    uint8_t windowsDown = 0; // bits 0-3: front left, front right, back left, back right wound down
    uint8_t doorsOpen = 0;   // bits 0-3: the same doors open or torn off
    bool openTop = false;    // a cabrio or targa, which has no roof

    bool Any() const
    {
        return glassGone != 0 || windowsDown != 0 || doorsOpen != 0 || openTop;
    }
    bool operator==(const CarStates& aOther) const
    {
        return glassGone == aOther.glassGone && windowsDown == aOther.windowsDown && doorsOpen == aOther.doorsOpen &&
               openTop == aOther.openTop;
    }
    bool operator!=(const CarStates& aOther) const
    {
        return !(*this == aOther);
    }
    std::string Describe() const; // for the log
};

// Where a car stands: its origin and axes in the world.
struct CarFrame
{
    Vec3 position;
    Vec3 right{1.f, 0.f, 0.f};
    Vec3 forward{0.f, 1.f, 0.f};
    Vec3 up{0.f, 0.f, 1.f};
};

// A mesh's own box from car_meshes.inc, false if the game files had no such mesh.
bool FindCarMeshBox(uint64_t aMesh, Vec3& aMin, Vec3& aMax);

// Whether an appearance, as the entity names it, has no roof.
bool IsOpenTopAppearance(const std::string& aAppearance);

class Car
{
public:
    // Starts describing a car afresh. aKey tells cars apart; the parts follow.
    void Begin(uint32_t aKey);
    // One part: aGlass is its index in the car record's glass list or -1, aDoor 0-3 for a door's main panel or -1. aPivot
    // is where the game puts the part, in the car's frame (metres right, forward, up), with everything shut.
    void AddPart(int aGlass, int aDoor, const std::string& aName, uint64_t aMesh, const Vec3& aPivot);
    // Works out the gaps once the parts are in.
    void Finish(const std::string& aAppearance);

    uint32_t Key() const
    {
        return m_key;
    }
    bool Described() const
    {
        return m_described;
    }
    bool OpenTop() const
    {
        return m_openTop;
    }
    int GapCount() const
    {
        return static_cast<int>(m_gaps.size());
    }
    int UnknownMeshes() const
    {
        return m_unknownMeshes;
    }

    // Eases each gap toward what's open and places them in the world. Glass breaks at once; windows and doors take their
    // time. The first update, or one after a long gap, goes straight there.
    void Update(const CarStates& aStates, const CarFrame& aFrame, double aNowMs);

    // The gaps that are at least a little open, in the world, as of the last Update.
    const std::vector<CarOpening>& Openings() const
    {
        return m_open;
    }

private:
    struct Part
    {
        int glass = -1;
        int door = -1;
        std::string name;
        Vec3 min;
        Vec3 max;
    };
    struct Gap
    {
        Vec3 centre; // in the car's frame
        Vec3 normal;
        float area = 0.f;
        int glass = -1;   // open when this glass is gone
        int wound = -1;   // or when this door's window is down
        int door = -1;    // or when this door is open (a door's whole gap)
        bool roof = false;
        float openness = 0.f;
    };

    uint32_t m_key = 0;
    bool m_described = false;
    bool m_openTop = false;
    int m_unknownMeshes = 0;
    std::vector<Part> m_parts;
    std::vector<Gap> m_gaps;
    std::vector<CarOpening> m_open;
    bool m_started = false;
    double m_lastMs = 0.0;
};
} // namespace nv
