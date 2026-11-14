#include "audio/car.hpp"

#include "audio/dsp.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>

namespace nv
{
namespace
{
struct MeshBox
{
    uint64_t mesh;
    float min[3];
    float max[3];
};

constexpr MeshBox kMeshes[] = {
#include "audio/car_meshes.inc"
};

constexpr const char* kOpenTops[] = {
#include "audio/car_open_tops.inc"
};

// A window winds and a door swings in about this long; glass breaks at once.
constexpr float kGapSeconds = 1.f;
constexpr double kSnapAfterMs = 2000.0;

float Dot3(const Vec3& aA, const Vec3& aB)
{
    return aA.x * aB.x + aA.y * aB.y + aA.z * aB.z;
}

float Length3(const Vec3& aV)
{
    return std::sqrt(Dot3(aV, aV));
}

Vec3 Scaled(const Vec3& aV, float aBy)
{
    return {aV.x * aBy, aV.y * aBy, aV.z * aBy};
}

Vec3 Plus(const Vec3& aA, const Vec3& aB)
{
    return {aA.x + aB.x, aA.y + aB.y, aA.z + aB.z};
}

// Which door a window part belongs to, from its name: window_fl, window_fl_a, window_fl_02 are the front left (0).
int DoorOfWindow(const std::string& aName)
{
    static const char* const kCodes[] = {"fl", "fr", "bl", "br"};
    for (int door = 0; door < 4; ++door)
    {
        const std::string prefix = std::string("window_") + kCodes[door];
        if (aName.compare(0, prefix.size(), prefix) == 0 && (aName.size() == prefix.size() || aName[prefix.size()] == '_'))
        {
            return door;
        }
    }
    return -1;
}

Vec3 InWorld(const CarFrame& aFrame, const Vec3& aLocal)
{
    return Plus(aFrame.position,
                Plus(Scaled(aFrame.right, aLocal.x), Plus(Scaled(aFrame.forward, aLocal.y), Scaled(aFrame.up, aLocal.z))));
}

Vec3 TurnedToWorld(const CarFrame& aFrame, const Vec3& aLocal)
{
    return Plus(Scaled(aFrame.right, aLocal.x), Plus(Scaled(aFrame.forward, aLocal.y), Scaled(aFrame.up, aLocal.z)));
}
} // namespace

std::string CarStates::Describe() const
{
    char text[128];
    std::snprintf(text, sizeof(text), "glass gone %#x, windows down %#x, doors open %#x%s", glassGone, windowsDown, doorsOpen,
                  openTop ? ", no roof" : "");
    return text;
}

bool FindCarMeshBox(uint64_t aMesh, Vec3& aMin, Vec3& aMax)
{
    const auto end = std::end(kMeshes);
    const auto it = std::lower_bound(std::begin(kMeshes), end, aMesh,
                                     [](const MeshBox& aBox, uint64_t aKey) { return aBox.mesh < aKey; });
    if (it == end || it->mesh != aMesh)
    {
        return false;
    }
    aMin = {it->min[0], it->min[1], it->min[2]};
    aMax = {it->max[0], it->max[1], it->max[2]};
    return true;
}

bool IsOpenTopAppearance(const std::string& aAppearance)
{
    return std::any_of(std::begin(kOpenTops), std::end(kOpenTops), [&](const char* aName) { return aAppearance == aName; });
}

void Car::Begin(uint32_t aKey)
{
    *this = Car();
    m_key = aKey;
}

void Car::AddPart(int aGlass, int aDoor, const std::string& aName, uint64_t aMesh, const Vec3& aPivot)
{
    Vec3 min;
    Vec3 max;
    if (!FindCarMeshBox(aMesh, min, max))
    {
        ++m_unknownMeshes; // a mod's car, or a patch since the table was made: this part stays shut
        return;
    }
    Part part;
    part.glass = aGlass;
    part.door = aDoor;
    part.name = aName;
    part.min = Plus(aPivot, min);
    part.max = Plus(aPivot, max);
    m_parts.push_back(part);
}

void Car::Finish(const std::string& aAppearance)
{
    m_gaps.clear();
    m_openTop = IsOpenTopAppearance(aAppearance);

    // The cabin's middle, from its glass, so each pane can tell which way is out.
    Vec3 middle{};
    int panes = 0;
    for (const Part& part : m_parts)
    {
        if (part.glass >= 0)
        {
            middle = Plus(middle, Scaled(Plus(part.min, part.max), 0.5f));
            ++panes;
        }
    }
    if (panes > 0)
    {
        middle = Scaled(middle, 1.f / static_cast<float>(panes));
    }

    // Each door's biggest window is the one that winds down.
    int wound[4] = {-1, -1, -1, -1};
    float woundArea[4] = {0.f, 0.f, 0.f, 0.f};
    float sideMinY = 1e9f;
    float sideMaxY = -1e9f;
    float sideTop = -1e9f;
    float leftX = 0.f;
    float rightX = 0.f;

    for (const Part& part : m_parts)
    {
        const Vec3 centre = Scaled(Plus(part.min, part.max), 0.5f);
        const Vec3 size{part.max.x - part.min.x, part.max.y - part.min.y, part.max.z - part.min.z};
        Gap gap;
        gap.centre = centre;
        if (part.door >= 0)
        {
            // A door's whole gap, on its side of the car.
            gap.door = part.door;
            gap.normal = {centre.x < 0.f ? -1.f : 1.f, 0.f, 0.f};
            gap.area = size.y * size.z;
        }
        else if (part.glass >= 0)
        {
            // A pane faces out of the cabin, across its longest side.
            gap.glass = part.glass;
            const float longest = std::max({size.x, size.y, size.z});
            Vec3 out{centre.x - middle.x, centre.y - middle.y, centre.z - middle.z};
            if (longest == size.x)
            {
                out.x = 0.f;
                gap.area = size.x * std::hypot(size.y, size.z);
            }
            else if (longest == size.y)
            {
                out.y = 0.f;
                gap.area = size.y * std::hypot(size.x, size.z);
            }
            else
            {
                out.z = 0.f;
                gap.area = size.z * std::hypot(size.x, size.y);
            }
            const float length = Length3(out);
            gap.normal = length > 0.01f ? Scaled(out, 1.f / length) : Vec3{centre.x < 0.f ? -1.f : 1.f, 0.f, 0.f};

            const int door = DoorOfWindow(part.name);
            if (door >= 0)
            {
                if (gap.area > woundArea[door])
                {
                    woundArea[door] = gap.area;
                    wound[door] = static_cast<int>(m_gaps.size());
                }
                sideMinY = std::min(sideMinY, part.min.y);
                sideMaxY = std::max(sideMaxY, part.max.y);
                sideTop = std::max(sideTop, part.max.z);
                (centre.x < 0.f ? leftX : rightX) = centre.x;
            }
        }
        else
        {
            continue;
        }
        m_gaps.push_back(gap);
    }
    for (int door = 0; door < 4; ++door)
    {
        if (wound[door] >= 0)
        {
            m_gaps[static_cast<size_t>(wound[door])].wound = door;
        }
    }

    // No roof: the whole top between the side windows.
    if (m_openTop && sideMaxY > sideMinY && rightX > leftX)
    {
        Gap roof;
        roof.roof = true;
        roof.centre = {0.5f * (leftX + rightX), 0.5f * (sideMinY + sideMaxY), sideTop};
        roof.normal = {0.f, 0.f, 1.f};
        roof.area = (sideMaxY - sideMinY) * (rightX - leftX);
        m_gaps.push_back(roof);
    }
    m_parts.clear();
    m_described = true;
    m_started = false;
}

void Car::Update(const CarStates& aStates, const CarFrame& aFrame, double aNowMs)
{
    const double elapsedMs = aNowMs - m_lastMs;
    const bool snap = !m_started || elapsedMs > kSnapAfterMs;
    const float step = snap ? 1.f : static_cast<float>(std::max(elapsedMs, 0.0) / 1000.0) / kGapSeconds;
    m_started = true;
    m_lastMs = aNowMs;

    m_open.clear();
    for (Gap& gap : m_gaps)
    {
        bool broken = false;
        bool open = false;
        if (gap.roof)
        {
            open = aStates.openTop;
        }
        else if (gap.door >= 0)
        {
            open = ((aStates.doorsOpen >> gap.door) & 1u) != 0;
        }
        else
        {
            broken = gap.glass < 32 && ((aStates.glassGone >> gap.glass) & 1u) != 0;
            const bool down = gap.wound >= 0 && ((aStates.windowsDown >> gap.wound) & 1u) != 0;
            const bool doorOpen = gap.wound >= 0 && ((aStates.doorsOpen >> gap.wound) & 1u) != 0;
            open = (broken || down) && !doorOpen; // an open door's gap takes its window in
        }
        const float target = open ? 1.f : 0.f;
        if (snap || (broken && target > gap.openness))
        {
            gap.openness = target;
        }
        else
        {
            gap.openness += std::clamp(target - gap.openness, -step, step);
        }
        if (gap.openness > 0.001f)
        {
            CarOpening opening;
            opening.centre = InWorld(aFrame, gap.centre);
            opening.normal = TurnedToWorld(aFrame, gap.normal);
            opening.area = gap.area;
            opening.openness = gap.openness;
            m_open.push_back(opening);
        }
    }
}
} // namespace nv
