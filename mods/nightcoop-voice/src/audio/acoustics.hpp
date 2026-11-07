// What the sound rays should ask and what the answers mean: the room around the listener, the walls between players, ways
// round those walls, and which surfaces give an echo. The game only casts the rays, so the test program can stand in for
// the world and check all of this. Game thread only, except where it says otherwise.
#pragma once

#include "audio/dsp.hpp"
#include "core/common.hpp"

#include <array>
#include <coroutine>
#include <memory>
#include <vector>

namespace nv
{
enum class RayGroups : int
{
    Walls = 0,         // the world's fixed geometry
    WallsAndDoors = 1, // and, if that's clear, whether a closed door is in the way
    DoorsOnly = 2,     // only that: for a stretch somebody has already walked
};

enum class RayResult : int
{
    Clear = 0,
    Wall = 1,
    ClosedDoor = 2,
};

struct RayRequest
{
    Vec3 from;
    Vec3 to;
    RayGroups groups = RayGroups::Walls;
};

struct RayAnswer
{
    RayResult result = RayResult::Clear;
    Vec3 position;
    Vec3 normal;           // all zeros if the game gave none
    float thinWall = 0.f;  // from ThinWallOcclusion
    float soft = 0.f;      // from SoftSurfaceAbsorbs
};

// For a material sound mostly passes through, how much it muffles when it fills the line between two players, with 1 for
// the thickest walls. 0 for everything else, which counts as a solid wall.
float ThinWallOcclusion(const char* aMaterial);

// For a soft material, how much of a sound it soaks up, 0 .. 1. 0 for everything else, which counts as an ordinary wall.
float SoftSurfaceAbsorbs(const char* aMaterial);

// A way round the walls to a talker.
struct SoundPath
{
    bool found = false;
    Vec3 arrival;       // the first bend the listener can see
    float meters = 0.f; // along it, from listener to talker
    float bends = 0.f;
    float doors = 0.f;  // closed doors along it
};

// A wall one of the listener's rays found, which can give an echo.
struct WallSurface
{
    bool hit = false;
    Vec3 point;
    Vec3 normal; // one metre long, facing the listener
};

constexpr int kWallDirections = 8;
using WallSurfaces = std::array<WallSurface, kWallDirections>;

// One echo as the mixer plays it. Slots stay with a direction in the world, so an echo moves smoothly instead of jumping
// between them as the listener walks.
struct EchoTap
{
    float delaySamples = 0.f; // after the voice itself
    float gainLeft = 0.f;
    float gainRight = 0.f;
    float lagLeft = 0.f;      // samples: reaches the far ear later
    float lagRight = 0.f;
};

constexpr int kEchoTaps = 4;
using EchoSet = std::array<EchoTap, kEchoTaps>;

// Mirrors the talker in each wall to find the echoes. aAmount scales them all: 0 when walls, cars or water are in the way.
EchoSet ComputeEchoes(const WallSurfaces& aWalls, const Vec3& aListener, const Vec3& aListenerRight, const Vec3& aTalker,
                      float aAmount, bool aHeadphones);

class RayJob
{
public:
    struct promise_type
    {
        RayJob get_return_object()
        {
            return RayJob(std::coroutine_handle<promise_type>::from_promise(*this));
        }
        std::suspend_always initial_suspend() noexcept
        {
            return {};
        }
        std::suspend_always final_suspend() noexcept
        {
            return {};
        }
        void return_void()
        {
        }
        void unhandled_exception()
        {
        }
    };

    RayJob() = default;
    explicit RayJob(std::coroutine_handle<promise_type> aHandle)
        : m_handle(aHandle)
    {
    }
    RayJob(RayJob&& aOther) noexcept
        : m_handle(aOther.m_handle)
    {
        aOther.m_handle = nullptr;
    }
    RayJob& operator=(RayJob&& aOther) noexcept
    {
        if (this != &aOther)
        {
            Reset();
            m_handle = aOther.m_handle;
            aOther.m_handle = nullptr;
        }
        return *this;
    }
    RayJob(const RayJob&) = delete;
    RayJob& operator=(const RayJob&) = delete;
    ~RayJob()
    {
        Reset();
    }

    void Reset()
    {
        if (m_handle)
        {
            m_handle.destroy();
            m_handle = nullptr;
        }
    }
    bool Running() const
    {
        return m_handle && !m_handle.done();
    }
    void Resume()
    {
        m_handle.resume();
    }

private:
    std::coroutine_handle<promise_type> m_handle;
};

class Acoustics
{
public:
    Acoustics();
    ~Acoustics();

    void SetListener(const Vec3& aPosition, double aNowMs);
    // aTalking: they've spoken lately, so what's between us is worth the rays. aCabin is a Cabin.
    void SetTalker(PeerId aPeer, const Vec3& aPosition, int aCabin, bool aTalking, double aNowMs);

    // The next ray to cast, if any is due. Its answer goes to ReportRay before the next call.
    bool NextRay(RayRequest& aRequest, double aNowMs);
    void ReportRay(const RayAnswer& aAnswer);

    float Occlusion(PeerId aPeer) const;
    SoundPath Path(PeerId aPeer) const;
    const RoomSound& Room() const
    {
        return m_room;
    }
    const WallSurfaces& Walls() const
    {
        return m_walls;
    }

    // One line for the log, every so often, then starts counting afresh.
    void LogStats();

private:
    struct Talker;
    friend struct CastAwaiter;

    Talker* Find(PeerId aPeer) const;
    void NoteTrail(std::vector<Vec3>& aTrail, const Vec3& aPosition);
    bool StartNextJob(double aNowMs);
    void ForgetOldTalkers(double aNowMs);

    RayJob MeasureRoom();
    RayJob MeasureWalls(PeerId aPeer);
    RayJob FindWayRound(PeerId aPeer);

    Vec3 m_listener;
    std::vector<Vec3> m_trail;
    std::vector<std::unique_ptr<Talker>> m_talkers;
    size_t m_cursor = 0;

    RoomSound m_room;
    WallSurfaces m_walls{};
    double m_nowMs = 0.0;
    double m_roomDueMs = 0.0;

    RayJob m_job;
    PeerId m_jobPeer = 0;
    bool m_jobHasPeer = false;
    RayRequest m_request;
    RayAnswer m_answer;
    bool m_requestWaiting = false;

    int m_roofedDirections = 0;
    int m_normalsFromGame = 0;
    int m_normalsGuessed = 0;
    int m_waysKept = 0;
    int m_waysTheirTrail = 0;
    int m_waysMyTrail = 0;
    int m_waysFan = 0;
    int m_waysNone = 0;
};
} // namespace nv
