#include "audio/acoustics.hpp"

#include "audio/spatial.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace nv
{
namespace
{
constexpr float kFarMeters = 50.f;     // no voice carries further, so neither ray nor way round needs to; as SpatialInput::farMeters
constexpr float kSpeedOfSound = 343.f;

// ---- the room
constexpr float kRoomReach = 40.f;
constexpr double kRoomEveryMs = 500.0;
constexpr float kSurfaceAbsorbs = 0.2f;     // walls with things in front of them; soft materials soak up more (SoftSurfaceAbsorbs)
constexpr float kLongWayAbsorbs = 0.1f;     // a long way off under a roof: a tunnel's far end, not open air
constexpr float kLongWayCloses = 0.7f;
constexpr float kRoofProbeAt = 0.6f;        // how far along a ray to look for a roof over that direction
constexpr float kRoofProbeFarthest = 12.f;  // and no further: a roof way off across open ground doesn't cover you
constexpr float kLowRoofMeters = 15.f;      // a roof this low closes a space in, whatever's around it
constexpr float kHighRoofMeters = 25.f;     // this high it still does, but only with walls close by, like a tall hall
constexpr float kNearWallMeters = 20.f;     // higher than that it's a building overhead, and sound goes up and doesn't come back
constexpr float kLowCeilingCloses = 0.6f;   // a low ceiling right above you gives something back, however open the ends
// A tunnel or a corridor holds on to sound along its length, and sounds as long as it is, not as narrow as it is. Wider than
// kLongSpaceMeters this stops applying, and it's in full by kNarrowSpaceMeters, once the long side is kLongSpaceToRatio times
// the typical width. A wide underpass is left alone: it already sounds right.
constexpr float kLongSpaceMeters = 8.f;
constexpr float kNarrowSpaceMeters = 5.f;
constexpr float kLongSpaceFromRatio = 2.f;
constexpr float kLongSpaceToRatio = 6.f;
constexpr float kLongSpaceRings = 1.f;      // up to this much longer again
constexpr float kLongSpaceSize = 0.5f;      // how far toward its length its echo spacing goes
constexpr float kOpenRingSeconds = 0.5f;    // the most a space rings for with kOpenRingDirections open sides
constexpr float kOpenRingDirections = 3.f;
constexpr float kOpenAirRingSeconds = 0.25f; // and with every side open
constexpr float kLowWallCheckFrom = 0.75f;  // nearer than this, the ray up its face can't tell anything
constexpr float kOpenSkyCloses = 0.15f;     // under open sky, sound leaves and very little of a room forms
constexpr float kMinWidthMeters = 0.5f;
constexpr float kMinDecaySeconds = 0.15f;
constexpr float kMaxDecaySeconds = 3.f;
constexpr float kEyringPerMeter = 0.04f;    // decay seconds per metre of mean free path, for each unit of absorption

// ---- walls between players
constexpr float kLineSpread = 0.35f;
constexpr double kWallsTalkingEveryMs = 200.0;
constexpr double kWallsQuietEveryMs = 1000.0;
constexpr float kWallsEase = 0.4f;
constexpr float kPastThinWall = 0.1f;

// ---- ways round
constexpr float kWayWantedOcclusion = 0.2f; // clipping a door frame isn't worth looking for another way
constexpr double kWayRetestEveryMs = 500.0;
constexpr double kWayRetryEveryMs = 1000.0;
constexpr double kFanEveryMs = 2000.0;
constexpr int kTrailPoints = 40;
constexpr float kTrailSpacing = 1.5f;
constexpr float kTrailJump = 8.f;           // further than this between updates isn't walking, or even driving
constexpr int kMaxDoorChecks = 16;
constexpr float kBendTolerance = 1.5f;      // wiggles smaller than this aren't corners
constexpr float kMaxDetour = 3.f;           // a route far longer than the straight line isn't how the sound got there
constexpr float kDetourSlack = 10.f;
constexpr int kFanDirections = 12;
constexpr float kFanStepDegrees = 30.f;
constexpr float kFanRotateDegrees = 11.25f; // each sweep looks between the last one's rays
constexpr float kFanReach = 20.f;
constexpr float kFanBehind = -0.3f;         // a bend almost never lies directly away from the talker
constexpr float kFanOffWall = 0.4f;
constexpr float kFanGoodEnough = 1.25f;     // of the straight line: stops the sweep early
constexpr std::array<std::array<float, 4>, 2> kFanSamples{{{1.5f, 3.5f, 7.f, 12.f}, {2.5f, 5.f, 9.f, 15.f}}};

// ---- echoes
constexpr float kEchoMinSeconds = 0.015f; // sooner than this just colours the voice, so the room's sound covers it
constexpr float kEchoMaxSamples = 15000.f;
constexpr float kEchoReflects = 0.45f;    // a real wall scatters and soaks up much of it
constexpr float kEchoMaxOfVoice = 0.35f;  // never within about 9 dB of the voice itself, however far off the talker is
constexpr float kEchoNearestWall = 2.5f;  // nearer than this, a bounce comes back too soon to be an echo
constexpr float kThinWallReflects = 0.2f; // ThinWallOcclusion below this lets too much through to throw much back
constexpr float kWallCheckUp = 1.5f;      // a surface must reach this far above where the ray hit it; much more would find the ceiling
constexpr float kWallCheckSide = 2.5f;    // and this far to each side, to give an echo
constexpr float kWallCheckReach = 1.3f;   // of the way to that point, so the ray gets past the wall if there's no wall there
constexpr float kWallCheckTolerance = 0.75f;
constexpr float kEchoSearchMin = 6.f;     // how far from where a ray landed the same wall can be trusted to go on
constexpr float kEchoSearchShare = 0.7f;
constexpr float kNearMeters = 2.f;
constexpr float kWallNormalMaxUp = 0.5f;  // steeper than this, it's a floor or a ceiling

constexpr double kForgetTalkerMs = 5000.0;

float Dot(const Vec3& aLeft, const Vec3& aRight)
{
    return aLeft.x * aRight.x + aLeft.y * aRight.y + aLeft.z * aRight.z;
}

Vec3 Add(const Vec3& aLeft, const Vec3& aRight)
{
    return {aLeft.x + aRight.x, aLeft.y + aRight.y, aLeft.z + aRight.z};
}

Vec3 Sub(const Vec3& aLeft, const Vec3& aRight)
{
    return {aLeft.x - aRight.x, aLeft.y - aRight.y, aLeft.z - aRight.z};
}

Vec3 Scale(const Vec3& aVector, float aAmount)
{
    return {aVector.x * aAmount, aVector.y * aAmount, aVector.z * aAmount};
}

float Length(const Vec3& aVector)
{
    return std::sqrt(Dot(aVector, aVector));
}

float DistanceBetween(const Vec3& aLeft, const Vec3& aRight)
{
    return Length(Sub(aLeft, aRight));
}

Vec3 Unit(const Vec3& aVector, const Vec3& aFallback = {1.f, 0.f, 0.f})
{
    const float length = Length(aVector);
    return length > 0.001f ? Scale(aVector, 1.f / length) : aFallback;
}

// Fixed in the world, not turning with the camera: looking at your feet doesn't change the room you're in.
Vec3 WallDirection(int aIndex)
{
    const float angle = static_cast<float>(aIndex) * 2.f * kPi / kWallDirections;
    return {std::cos(angle), std::sin(angle), 0.f};
}

bool LetsSoundThrough(const RayAnswer& aAnswer)
{
    return aAnswer.result == RayResult::Clear || (aAnswer.result == RayResult::Wall && aAnswer.thinWall > 0.f);
}

float DistanceFromSegment(const Vec3& aPoint, const Vec3& aFrom, const Vec3& aTo)
{
    const Vec3 along = Sub(aTo, aFrom);
    const float lengthSquared = Dot(along, along);
    const float t = lengthSquared > 1e-6f ? std::clamp(Dot(Sub(aPoint, aFrom), along) / lengthSquared, 0.f, 1.f) : 0.f;
    return DistanceBetween(aPoint, Add(aFrom, Scale(along, t)));
}

// Marks the points of a walked route that matter, leaving out the wiggles.
void KeepCorners(const std::vector<Vec3>& aPoints, size_t aFirst, size_t aLast, std::vector<bool>& aKeep)
{
    if (aLast <= aFirst + 1)
    {
        return;
    }
    float furthest = 0.f;
    size_t at = aFirst;
    for (size_t i = aFirst + 1; i < aLast; ++i)
    {
        const float away = DistanceFromSegment(aPoints[i], aPoints[aFirst], aPoints[aLast]);
        if (away > furthest)
        {
            furthest = away;
            at = i;
        }
    }
    if (furthest > kBendTolerance)
    {
        aKeep[at] = true;
        KeepCorners(aPoints, aFirst, at, aKeep);
        KeepCorners(aPoints, at, aLast, aKeep);
    }
}

// How long a walked route is, with the wiggles taken out, and how many corners it has.
void MeasureRoute(const std::vector<Vec3>& aPoints, float& aMeters, float& aBends)
{
    std::vector<bool> keep(aPoints.size(), false);
    keep.front() = true;
    keep.back() = true;
    KeepCorners(aPoints, 0, aPoints.size() - 1, keep);
    aMeters = 0.f;
    int corners = -1;
    size_t previous = 0;
    for (size_t i = 0; i < aPoints.size(); ++i)
    {
        if (keep[i])
        {
            if (i > 0)
            {
                aMeters += DistanceBetween(aPoints[previous], aPoints[i]);
            }
            previous = i;
            ++corners;
        }
    }
    // The walls say there's at least one, whatever the route's shape.
    aBends = static_cast<float>(std::max(corners, 1));
}
} // namespace

float ThinWallOcclusion(const char* aMaterial)
{
    struct Thin
    {
        const char* name;
        float occlusion;
    };
    // A window still stops a lot; a grate or a catwalk hardly anything.
    static constexpr Thin kThin[] = {
        {"glass.physmat", 0.35f},
        {"glass_dst.physmat", 0.35f},
        {"glass_semitransparent.physmat", 0.25f},
        {"plexiglass.physmat", 0.4f},
        {"metal_transparent.physmat", 0.08f},
        {"metal_semitransparent.physmat", 0.15f},
        {"metal_catwalk.physmat", 0.05f},
        {"leaves.physmat", 0.1f},
        {"leaves_semitransparent.physmat", 0.05f},
        {"wood_hedge.physmat", 0.1f},
        {"wood_crown.physmat", 0.1f},
    };
    if (aMaterial)
    {
        for (const Thin& thin : kThin)
        {
            if (std::strcmp(aMaterial, thin.name) == 0)
            {
                return thin.occlusion;
            }
        }
    }
    return 0.f;
}

float SoftSurfaceAbsorbs(const char* aMaterial)
{
    struct Soft
    {
        const char* name;
        float absorbs;
    };
    // Only what's softer than an ordinary wall. Concrete, metal and tiles stay as they are, since rooms are tuned by ear on them.
    static constexpr Soft kSoft[] = {
        {"fabrics.physmat", 0.5f},
        {"carpet.physmat", 0.5f},
        {"carpet_techpiercable.physmat", 0.5f},
        {"furniture_upholstery.physmat", 0.6f},
        {"upholstery_car.physmat", 0.5f},
        {"furniture_leather.physmat", 0.4f},
        {"leather.physmat", 0.4f},
        {"cardboard.physmat", 0.3f},
        {"paper.physmat", 0.3f},
        {"trash_bag.physmat", 0.3f},
        {"grass.physmat", 0.4f},
        {"sand.physmat", 0.4f},
        {"dirt.physmat", 0.3f},
        {"mud.physmat", 0.3f},
        {"leaves.physmat", 0.5f},
        {"leaves_semitransparent.physmat", 0.5f},
        {"wood_hedge.physmat", 0.5f},
        {"wood_crown.physmat", 0.5f},
    };
    if (aMaterial)
    {
        for (const Soft& soft : kSoft)
        {
            if (std::strcmp(aMaterial, soft.name) == 0)
            {
                return soft.absorbs;
            }
        }
    }
    return 0.f;
}

EchoSet ComputeEchoes(const WallSurfaces& aWalls, const Vec3& aListener, const Vec3& aListenerRight, const Vec3& aTalker,
                      float aAmount, bool aHeadphones)
{
    EchoSet taps{};
    if (aAmount <= 0.f)
    {
        return taps;
    }
    const float straight = DistanceBetween(aListener, aTalker);
    const float tuned = std::pow(10.f, g_liveTuning.echoDb.load() / 20.f);
    std::array<float, kEchoTaps> loudest{};

    for (int i = 0; i < kWallDirections; ++i)
    {
        const WallSurface& wall = aWalls[static_cast<size_t>(i)];
        if (!wall.hit)
        {
            continue;
        }
        const float talkerSide = Dot(Sub(aTalker, wall.point), wall.normal);
        if (talkerSide <= 0.f)
        {
            continue; // they're behind this wall, so it can't bounce their voice to the listener
        }
        const Vec3 mirrored = Sub(aTalker, Scale(wall.normal, 2.f * talkerSide));
        const float bounced = DistanceBetween(aListener, mirrored);
        const float delaySeconds = (bounced - straight) / kSpeedOfSound;
        const float delaySamples = delaySeconds * kRate;
        if (delaySeconds < kEchoMinSeconds || delaySamples > kEchoMaxSamples)
        {
            continue;
        }

        // Where the bounce would land. If that's far from anywhere a ray has seen this wall, the wall may not reach that far.
        const float listenerSide = Dot(Sub(aListener, wall.point), wall.normal);
        if (listenerSide <= 0.f)
        {
            continue;
        }
        const Vec3 bounce = Add(aListener, Scale(Sub(mirrored, aListener), listenerSide / (listenerSide + talkerSide)));
        if (DistanceBetween(bounce, wall.point) > std::max(kEchoSearchMin, listenerSide * kEchoSearchShare))
        {
            continue;
        }

        const float gain = std::min(RolloffGain(bounced, kNearMeters) * kEchoReflects, RolloffGain(straight, kNearMeters) * kEchoMaxOfVoice) * aAmount * tuned;
        const size_t slot = static_cast<size_t>(i) * kEchoTaps / kWallDirections;
        if (gain <= loudest[slot])
        {
            continue;
        }
        loudest[slot] = gain;

        const Vec3 direction = Unit(Sub(mirrored, aListener));
        const EarGains ears = EarsFor(std::clamp(Dot(direction, aListenerRight), -1.f, 1.f), aHeadphones);
        EchoTap& tap = taps[slot];
        tap.delaySamples = delaySamples;
        tap.gainLeft = gain * ears.left;
        tap.gainRight = gain * ears.right;
        tap.lagLeft = ears.lagLeft;
        tap.lagRight = ears.lagRight;
    }
    return taps;
}

struct Acoustics::Talker
{
    PeerId id = 0;
    Vec3 position;
    int cabin = CabinNone;
    bool talking = false;
    double seenMs = 0.0;

    bool measured = false;
    float occlusion = 0.f;
    double wallsDueMs = 0.0;

    SoundPath path;
    Vec3 pathLast;            // the last point before the talker, retested with the first bend
    float pathMiddle = 0.f;   // metres between the first bend and that point
    double pathDueMs = 0.0;
    double fanDueMs = 0.0;
    int fanSweep = 0;

    std::vector<Vec3> trail;
};

Acoustics::Acoustics() = default;
Acoustics::~Acoustics() = default;

// What a job awaits: hands its ray over, and carries on with the answer once it's been cast.
struct CastAwaiter
{
    Acoustics& owner;
    RayRequest request;

    bool await_ready() const noexcept
    {
        return false;
    }
    void await_suspend(std::coroutine_handle<>) noexcept
    {
        owner.m_request = request;
        owner.m_requestWaiting = true;
    }
    RayAnswer await_resume() const noexcept
    {
        return owner.m_answer;
    }
};

Acoustics::Talker* Acoustics::Find(PeerId aPeer) const
{
    for (const auto& talker : m_talkers)
    {
        if (talker->id == aPeer)
        {
            return talker.get();
        }
    }
    return nullptr;
}

void Acoustics::NoteTrail(std::vector<Vec3>& aTrail, const Vec3& aPosition)
{
    if (!aTrail.empty())
    {
        const float moved = DistanceBetween(aTrail.back(), aPosition);
        if (moved >= kTrailJump)
        {
            aTrail.clear(); // fast travel, a respawn, a load: the walk so far doesn't lead here
        }
        else if (moved < kTrailSpacing)
        {
            return;
        }
    }
    if (aTrail.size() == kTrailPoints)
    {
        aTrail.erase(aTrail.begin());
    }
    aTrail.push_back(aPosition);
}

void Acoustics::SetListener(const Vec3& aPosition, double aNowMs)
{
    m_listener = aPosition;
    m_nowMs = aNowMs;
    NoteTrail(m_trail, aPosition);
}

void Acoustics::SetTalker(PeerId aPeer, const Vec3& aPosition, int aCabin, bool aTalking, double aNowMs)
{
    Talker* talker = Find(aPeer);
    if (!talker)
    {
        auto added = std::make_unique<Talker>();
        added->id = aPeer;
        talker = added.get();
        m_talkers.push_back(std::move(added));
    }
    talker->position = aPosition;
    talker->cabin = aCabin;
    talker->talking = aTalking;
    talker->seenMs = aNowMs;
    NoteTrail(talker->trail, aPosition);
}

float Acoustics::Occlusion(PeerId aPeer) const
{
    const Talker* talker = Find(aPeer);
    return talker ? talker->occlusion : 0.f;
}

SoundPath Acoustics::Path(PeerId aPeer) const
{
    const Talker* talker = Find(aPeer);
    return talker ? talker->path : SoundPath{};
}

void Acoustics::ForgetOldTalkers(double aNowMs)
{
    for (size_t i = m_talkers.size(); i-- > 0;)
    {
        if (aNowMs - m_talkers[i]->seenMs > kForgetTalkerMs)
        {
            if (m_jobHasPeer && m_jobPeer == m_talkers[i]->id)
            {
                m_job.Reset();
                m_jobHasPeer = false;
                m_requestWaiting = false;
            }
            m_talkers.erase(m_talkers.begin() + static_cast<ptrdiff_t>(i));
        }
    }
}

bool Acoustics::StartNextJob(double aNowMs)
{
    if (m_talkers.empty())
    {
        return false; // alone in the world: nobody to hear, and nobody's voice to hear
    }
    m_jobHasPeer = false;
    if (aNowMs >= m_roomDueMs)
    {
        m_roomDueMs = aNowMs + kRoomEveryMs;
        m_job = MeasureRoom();
        return true;
    }

    // Whoever's turn it is, so that one player's walls and corners can't starve another's.
    for (size_t i = 0; i < m_talkers.size(); ++i)
    {
        Talker& talker = *m_talkers[(m_cursor + i) % m_talkers.size()];
        const float straight = DistanceBetween(m_listener, talker.position);
        const bool reachable = straight < kFarMeters && talker.cabin != CabinShared &&
                               ShouldSendNearby(straight, talker.cabin == CabinSeparated ? 1.f : 0.f, kFarMeters);
        if (!reachable)
        {
            // Nothing to hear, so nothing to measure. Walls and ways round start from what's true when that changes.
            talker.occlusion = 0.f;
            talker.measured = false;
            talker.path.found = false;
            continue;
        }
        if (aNowMs >= talker.wallsDueMs)
        {
            talker.wallsDueMs = aNowMs + (talker.talking ? kWallsTalkingEveryMs : kWallsQuietEveryMs);
            m_cursor = (m_cursor + i + 1) % m_talkers.size();
            m_jobPeer = talker.id;
            m_jobHasPeer = true;
            m_job = MeasureWalls(talker.id);
            return true;
        }
        if (talker.talking && talker.occlusion >= kWayWantedOcclusion && aNowMs >= talker.pathDueMs)
        {
            talker.pathDueMs = aNowMs + kWayRetryEveryMs;
            m_cursor = (m_cursor + i + 1) % m_talkers.size();
            m_jobPeer = talker.id;
            m_jobHasPeer = true;
            m_job = FindWayRound(talker.id);
            return true;
        }
        if (talker.occlusion < kWayWantedOcclusion)
        {
            talker.path.found = false;
        }
    }
    return false;
}

bool Acoustics::NextRay(RayRequest& aRequest, double aNowMs)
{
    m_nowMs = aNowMs;
    ForgetOldTalkers(aNowMs);
    for (int guard = 0; guard < 64; ++guard)
    {
        if (!m_job.Running())
        {
            if (!StartNextJob(aNowMs))
            {
                return false;
            }
        }
        m_requestWaiting = false;
        m_job.Resume();
        if (m_requestWaiting)
        {
            aRequest = m_request;
            return true;
        }
        // It finished without another ray: the next job's turn.
    }
    return false;
}

void Acoustics::ReportRay(const RayAnswer& aAnswer)
{
    m_answer = aAnswer;
}

RayJob Acoustics::MeasureRoom()
{
    const Vec3 from = m_listener;
    const Vec3 up{0.f, 0.f, 1.f};

    const RayAnswer above = co_await CastAwaiter{*this, {from, Add(from, Scale(up, kRoomReach)), RayGroups::Walls}};
    const RayAnswer below = co_await CastAwaiter{*this, {from, Sub(from, Scale(up, kRoomReach)), RayGroups::Walls}};
    const bool ground = below.result == RayResult::Wall;
    const float hitMeters = above.result == RayResult::Wall ? DistanceBetween(from, above.position) : kRoomReach;
    const bool ceiling = hitMeters <= kHighRoofMeters;
    const bool lowCeiling = hitMeters <= kLowRoofMeters;
    const float upMeters = ceiling ? hitMeters : kRoomReach;
    const float downMeters = ground ? DistanceBetween(from, below.position) : kRoomReach;

    WallSurfaces walls{};
    std::array<float, kWallDirections> reached{};
    std::array<bool, kWallDirections> stopped{};
    std::array<bool, kWallDirections> roofed{};
    std::array<float, kWallDirections> surface{};
    for (int i = 0; i < kWallDirections; ++i)
    {
        const auto index = static_cast<size_t>(i);
        const Vec3 direction = WallDirection(i);
        const RayAnswer answer = co_await CastAwaiter{*this, {from, Add(from, Scale(direction, kRoomReach)), RayGroups::Walls}};
        stopped[index] = answer.result == RayResult::Wall;
        surface[index] = std::max(kSurfaceAbsorbs, answer.soft);
        reached[index] = stopped[index] ? DistanceBetween(from, answer.position) : kRoomReach;

        // Is there a roof out that way? A ceiling overhead and a building across the courtyard don't make a balcony a room:
        // sound leaves through the open side and doesn't come back. Under a real roof, this finds the roof.
        const Vec3 outThere = Add(from, Scale(direction, std::min(reached[index] * kRoofProbeAt, kRoofProbeFarthest)));
        const RayAnswer roof = co_await CastAwaiter{*this, {outThere, Add(outThere, Scale(up, kRoomReach)), RayGroups::Walls}};
        if (roof.result == RayResult::Wall)
        {
            const float height = DistanceBetween(outThere, roof.position);
            roofed[index] = height <= kLowRoofMeters || (height <= kHighRoofMeters && stopped[index] && reached[index] <= kNearWallMeters);
        }

        if (!stopped[index])
        {
            continue;
        }

        // The game's normal if it gave a sensible one, else assume the wall faces the ray.
        WallSurface& wall = walls[static_cast<size_t>(i)];
        const float normalLength = Length(answer.normal);
        const bool usable = normalLength > 0.9f && normalLength < 1.1f && Dot(answer.normal, direction) < -0.05f;
        if (usable)
        {
            ++m_normalsFromGame;
            if (std::fabs(answer.normal.z) > kWallNormalMaxUp)
            {
                continue; // a ramp or a ledge: a bounce off it goes up or down, not to anyone's ears
            }
            wall.normal = Unit(answer.normal);
        }
        else
        {
            ++m_normalsGuessed;
            wall.normal = Scale(direction, -1.f);
        }

        // Does it go up past head height? A ray at head height stops at a low wall, but sound goes straight over the top, so
        // that way is open, however much roof is around. Anything nearer than the wall is fine, like a low ceiling in a room:
        // it only fails if the ray gets beyond the wall's plane, as it does over a flight of stairs.
        const auto stopsRayToward = [&](const RayAnswer& aPast) {
            return aPast.result == RayResult::Wall && Dot(Sub(aPast.position, answer.position), wall.normal) > -kWallCheckTolerance;
        };
        if (reached[index] >= kLowWallCheckFrom)
        {
            const Vec3 towards = Sub(Add(answer.position, Scale(up, kWallCheckUp)), from);
            const RayAnswer over = co_await CastAwaiter{*this, {from, Add(from, Scale(towards, kWallCheckReach)), RayGroups::Walls}};
            if (!stopsRayToward(over))
            {
                stopped[index] = false;
                roofed[index] = false;
                continue;
            }
        }

        // Leaves and grates don't throw a voice back, and nor does anything soft.
        if ((answer.thinWall > 0.f && answer.thinWall < kThinWallReflects) || answer.soft > 0.f)
        {
            continue;
        }

        // Only something big gives an echo: a voice goes round a post or a sign. So before calling this a wall, look past it
        // to both sides. Close walls don't need this: they're heard as the room's sound, never as an echo.
        bool big = true;
        if (reached[index] >= kEchoNearestWall)
        {
            const Vec3 along = Unit(Vec3{-wall.normal.y, wall.normal.x, 0.f});
            const std::array<Vec3, 2> offsets{Scale(along, kWallCheckSide), Scale(along, -kWallCheckSide)};
            for (size_t check = 0; check < offsets.size() && big; ++check)
            {
                const Vec3 towards = Sub(Add(answer.position, offsets[check]), from);
                const RayAnswer past = co_await CastAwaiter{*this, {from, Add(from, Scale(towards, kWallCheckReach)), RayGroups::Walls}};
                big = stopsRayToward(past);
            }
        }
        if (big)
        {
            wall.hit = true;
            wall.point = answer.position;
        }
    }

    float totalMeters = upMeters + downMeters;
    float absorbs = (ceiling ? std::max(kSurfaceAbsorbs, above.soft) : 1.f) + (ground ? std::max(kSurfaceAbsorbs, below.soft) : 1.f);
    float closes = (ceiling ? 1.f : 0.f) + (ground ? 1.f : 0.f);
    int roofedDirections = 0;
    for (size_t i = 0; i < reached.size(); ++i)
    {
        totalMeters += reached[i];
        roofedDirections += roofed[i] ? 1 : 0;
        absorbs += !roofed[i] ? 1.f : stopped[i] ? surface[i] : kLongWayAbsorbs;
        closes += stopped[i] ? 1.f : roofed[i] ? kLongWayCloses : 0.f;
    }

    // How far sound goes between bounces is set by a space's narrow side, not its long one: 4 V / S for a tunnel is about its
    // width, however long it is. Opposite directions are added together, so standing beside a wall doesn't change the room.
    float inverseWidths = 0.f;
    float longestWidth = 0.f;
    int widths = 0;
    const auto addWidth = [&](float aWidth) {
        inverseWidths += 1.f / std::max(aWidth, kMinWidthMeters);
        longestWidth = std::max(longestWidth, aWidth);
        ++widths;
    };
    if (ceiling && ground)
    {
        addWidth((upMeters + downMeters) * 0.5f);
    }
    for (size_t i = 0; i < reached.size() / 2; ++i)
    {
        const size_t opposite = i + reached.size() / 2;
        if (roofed[i] && roofed[opposite])
        {
            addWidth((reached[i] + reached[opposite]) * 0.5f);
        }
        else if (roofed[i] || roofed[opposite])
        {
            addWidth(roofed[i] ? reached[i] : reached[opposite]); // only as far as the side that isn't open
        }
    }
    if (widths == 0)
    {
        // Nothing roofed: an alley or a square. It's still the walls that set how far sound goes.
        for (size_t i = 0; i < reached.size() / 2; ++i)
        {
            addWidth((reached[i] + reached[i + reached.size() / 2]) * 0.5f);
        }
    }

    const float rays = static_cast<float>(kWallDirections + 2);
    const float meanFreePath = static_cast<float>(widths) / inverseWidths;
    const float absorption = std::min(absorbs / rays, 0.98f);
    const float roofShare = static_cast<float>(roofedDirections) / kWallDirections;
    const float closedInShare = closes / rays;

    // Sound that leaves through an open side doesn't come back, however far off the other surfaces are.
    const float openSides = static_cast<float>(kWallDirections - roofedDirections);
    const float longestRing = openSides <= kOpenRingDirections
                                  ? kMaxDecaySeconds + (kOpenRingSeconds - kMaxDecaySeconds) * (openSides / kOpenRingDirections)
                                  : kOpenRingSeconds + (kOpenAirRingSeconds - kOpenRingSeconds) *
                                                           ((openSides - kOpenRingDirections) / (kWallDirections - kOpenRingDirections));
    const float longSpace = Clamp01((longestWidth / meanFreePath - kLongSpaceFromRatio) / (kLongSpaceToRatio - kLongSpaceFromRatio)) *
                            Clamp01((kLongSpaceMeters - meanFreePath) / (kLongSpaceMeters - kNarrowSpaceMeters));

    RoomSound room;
    room.meters = meanFreePath + (longestWidth - meanFreePath) * kLongSpaceSize * longSpace;
    room.enclosure = closedInShare * std::max(kOpenSkyCloses + (1.f - kOpenSkyCloses) * roofShare * roofShare * roofShare,
                                              lowCeiling ? kLowCeilingCloses : 0.f);
    room.decaySeconds = std::clamp(kEyringPerMeter * meanFreePath / -std::log(1.f - absorption) * (1.f + kLongSpaceRings * longSpace), kMinDecaySeconds, longestRing);
    m_room = room;
    m_walls = walls;
    m_roofedDirections = roofedDirections;
}

RayJob Acoustics::MeasureWalls(PeerId aPeer)
{
    Talker* talker = Find(aPeer);
    if (!talker)
    {
        co_return;
    }
    const Vec3 from = m_listener;
    const Vec3 to = talker->position;
    const Vec3 along = Unit(Sub(to, from));
    const Vec3 up{0.f, 0.f, 1.f};
    // Across the line itself, not across the camera: the spread is then the same whichever way anyone looks.
    const Vec3 across = Scale(Unit(Vec3{along.y, -along.x, 0.f}), kLineSpread);
    const std::array<Vec3, 5> offsets{Vec3{}, across, Scale(across, -1.f), Scale(up, kLineSpread), Scale(up, -kLineSpread)};

    float walls = 0.f;
    float doors = 0.f;
    float thin = 0.f;
    float thickness = 0.f;
    for (size_t i = 0; i < offsets.size(); ++i)
    {
        const Vec3 start = Add(from, offsets[i]);
        const Vec3 end = Add(to, offsets[i]);
        RayAnswer answer = co_await CastAwaiter{*this, {start, end, RayGroups::WallsAndDoors}};

        // A window or a grate: what matters is whether there's a real wall behind it.
        if (answer.result == RayResult::Wall && answer.thinWall > 0.f)
        {
            thin += answer.thinWall;
            answer = co_await CastAwaiter{*this, {Add(answer.position, Scale(along, kPastThinWall)), end, RayGroups::WallsAndDoors}};
            if (answer.result == RayResult::Wall && answer.thinWall > 0.f)
            {
                thin += answer.thinWall;
                continue;
            }
        }
        if (answer.result == RayResult::ClosedDoor)
        {
            doors += 1.f;
        }
        else if (answer.result == RayResult::Wall)
        {
            walls += 1.f;
            if (i == 0)
            {
                // Traced from both ends, it tells a thin wall from a whole building.
                const Vec3 nearSide = answer.position;
                const RayAnswer back = co_await CastAwaiter{*this, {to, from, RayGroups::Walls}};
                if (back.result == RayResult::Wall)
                {
                    thickness = DistanceBetween(nearSide, back.position);
                }
            }
        }
    }

    const float measured = std::min((walls / 5.f) * (0.6f + 0.4f * std::min(thickness / 6.f, 1.f)) + (doors / 5.f) * 0.55f + thin / 5.f, 1.f);
    // Nobody's speaking, so nobody hears it jump, and the first word has the right walls.
    const bool snap = !talker->measured || !talker->talking;
    talker->occlusion = snap ? measured : talker->occlusion + (measured - talker->occlusion) * kWallsEase;
    talker->measured = true;
}

RayJob Acoustics::FindWayRound(PeerId aPeer)
{
    Talker* talker = Find(aPeer);
    if (!talker)
    {
        co_return;
    }
    const Vec3 from = m_listener;
    const Vec3 to = talker->position;
    const float straight = DistanceBetween(from, to);
    const float longest = std::min(kFarMeters, straight * kMaxDetour + kDetourSlack);

    // Is the way we knew still open? Far cheaper than finding it again.
    if (talker->path.found)
    {
        const RayAnswer first = co_await CastAwaiter{*this, {from, talker->path.arrival, RayGroups::WallsAndDoors}};
        if (LetsSoundThrough(first))
        {
            const RayAnswer last = co_await CastAwaiter{*this, {talker->pathLast, to, RayGroups::WallsAndDoors}};
            if (LetsSoundThrough(last))
            {
                const float meters = DistanceBetween(from, talker->path.arrival) + talker->pathMiddle + DistanceBetween(talker->pathLast, to);
                if (meters <= longest)
                {
                    talker->path.meters = meters;
                    talker->pathDueMs = m_nowMs + kWayRetestEveryMs;
                    ++m_waysKept;
                    co_return;
                }
            }
        }
    }

    // Where they walked: they got there on foot, so it leads somewhere sound can follow. Look from their end back for the
    // newest point the listener can see, doubling the step, then close in on it.
    const std::vector<Vec3> theirs = talker->trail;
    int seen = -1;
    int blocked = static_cast<int>(theirs.size());
    for (int index = static_cast<int>(theirs.size()) - 1, step = 1; blocked > 0;)
    {
        index = std::max(index, 0);
        const RayAnswer answer = co_await CastAwaiter{*this, {from, theirs[static_cast<size_t>(index)], RayGroups::WallsAndDoors}};
        if (LetsSoundThrough(answer))
        {
            seen = index;
            break;
        }
        blocked = index;
        index -= step;
        step *= 2;
    }
    if (seen >= 0)
    {
        while (blocked - seen > 1)
        {
            const int middle = (blocked + seen) / 2;
            const RayAnswer answer = co_await CastAwaiter{*this, {from, theirs[static_cast<size_t>(middle)], RayGroups::WallsAndDoors}};
            if (LetsSoundThrough(answer))
            {
                seen = middle;
            }
            else
            {
                blocked = middle;
            }
        }

        std::vector<Vec3> route{from};
        route.insert(route.end(), theirs.begin() + seen, theirs.end());
        route.push_back(to);
        float meters = 0.f;
        float bends = 0.f;
        MeasureRoute(route, meters, bends);
        const RayAnswer last = co_await CastAwaiter{*this, {theirs.back(), to, RayGroups::WallsAndDoors}};
        if (meters <= longest && LetsSoundThrough(last))
        {
            float doors = 0.f;
            const int end = std::min(static_cast<int>(theirs.size()) - 1, seen + kMaxDoorChecks);
            for (int i = seen; i < end; ++i)
            {
                const RayAnswer hop = co_await CastAwaiter{*this, {theirs[static_cast<size_t>(i)], theirs[static_cast<size_t>(i) + 1], RayGroups::DoorsOnly}};
                doors += hop.result == RayResult::ClosedDoor ? 1.f : 0.f;
            }
            const Vec3 arrival = theirs[static_cast<size_t>(seen)];
            talker->path = {true, arrival, meters, bends, doors};
            talker->pathLast = theirs.back();
            talker->pathMiddle = std::max(meters - DistanceBetween(from, arrival) - DistanceBetween(theirs.back(), to), 0.f);
            talker->pathDueMs = m_nowMs + kWayRetestEveryMs;
            ++m_waysTheirTrail;
            co_return;
        }
    }

    // Where the listener walked, when it's them that moved away: the newest point of it the talker can see, and then how
    // far back along it the listener can still see.
    const std::vector<Vec3> mine = m_trail;
    int reached = -1;
    {
        int gone = static_cast<int>(mine.size());
        for (int index = static_cast<int>(mine.size()) - 1, step = 1; gone > 0;)
        {
            index = std::max(index, 0);
            const RayAnswer answer = co_await CastAwaiter{*this, {to, mine[static_cast<size_t>(index)], RayGroups::WallsAndDoors}};
            if (LetsSoundThrough(answer))
            {
                reached = index;
                break;
            }
            gone = index;
            index -= step;
            step *= 2;
        }
        while (reached >= 0 && gone - reached > 1)
        {
            const int middle = (gone + reached) / 2;
            const RayAnswer answer = co_await CastAwaiter{*this, {to, mine[static_cast<size_t>(middle)], RayGroups::WallsAndDoors}};
            if (LetsSoundThrough(answer))
            {
                reached = middle;
            }
            else
            {
                gone = middle;
            }
        }
    }
    if (reached >= 0)
    {
        // From the listener's end: the furthest point they can see, between where the talker can reach and where they stand.
        int visible = static_cast<int>(mine.size()) - 1;
        int hidden = reached - 1;
        const RayAnswer whole = co_await CastAwaiter{*this, {from, mine[static_cast<size_t>(reached)], RayGroups::WallsAndDoors}};
        if (LetsSoundThrough(whole))
        {
            visible = reached;
        }
        else
        {
            hidden = reached;
        }
        while (visible - hidden > 1)
        {
            const int middle = (visible + hidden) / 2;
            const RayAnswer answer = co_await CastAwaiter{*this, {from, mine[static_cast<size_t>(middle)], RayGroups::WallsAndDoors}};
            if (LetsSoundThrough(answer))
            {
                visible = middle;
            }
            else
            {
                hidden = middle;
            }
        }

        std::vector<Vec3> route{from};
        for (int i = static_cast<int>(mine.size()) - 1; i >= reached; --i)
        {
            if (i <= visible)
            {
                route.push_back(mine[static_cast<size_t>(i)]);
            }
        }
        route.push_back(to);
        float meters = 0.f;
        float bends = 0.f;
        MeasureRoute(route, meters, bends);
        if (meters <= longest)
        {
            float doors = 0.f;
            const int end = std::min(visible, reached + kMaxDoorChecks);
            for (int i = reached; i < end; ++i)
            {
                const RayAnswer hop = co_await CastAwaiter{*this, {mine[static_cast<size_t>(i)], mine[static_cast<size_t>(i) + 1], RayGroups::DoorsOnly}};
                doors += hop.result == RayResult::ClosedDoor ? 1.f : 0.f;
            }
            const Vec3 arrival = mine[static_cast<size_t>(visible)];
            const Vec3 lastPoint = mine[static_cast<size_t>(reached)];
            talker->path = {true, arrival, meters, bends, doors};
            talker->pathLast = lastPoint;
            talker->pathMiddle = std::max(meters - DistanceBetween(from, arrival) - DistanceBetween(lastPoint, to), 0.f);
            talker->pathDueMs = m_nowMs + kWayRetestEveryMs;
            ++m_waysMyTrail;
            co_return;
        }
    }

    // Nobody walked it. Look around for a corner: rays out from the listener, and points along them that can see the talker.
    if (m_nowMs >= talker->fanDueMs)
    {
        talker->fanDueMs = m_nowMs + kFanEveryMs;
        const float rotation = static_cast<float>(talker->fanSweep) * kFanRotateDegrees;
        const auto& samples = kFanSamples[static_cast<size_t>(talker->fanSweep) % kFanSamples.size()];
        ++talker->fanSweep;
        const Vec3 towards = Unit(Vec3{to.x - from.x, to.y - from.y, 0.f});

        float best = longest;
        Vec3 bestPoint;
        bool found = false;
        for (int d = 0; d < kFanDirections && !(found && best <= straight * kFanGoodEnough); ++d)
        {
            const float angle = (static_cast<float>(d) * kFanStepDegrees + rotation) * kPi / 180.f;
            const Vec3 direction{std::cos(angle), std::sin(angle), 0.f};
            if (Dot(direction, towards) < kFanBehind)
            {
                continue;
            }
            const RayAnswer out = co_await CastAwaiter{*this, {from, Add(from, Scale(direction, kFanReach)), RayGroups::WallsAndDoors}};
            const float open = LetsSoundThrough(out) ? kFanReach : DistanceBetween(from, out.position) - kFanOffWall;
            for (float sample : samples)
            {
                const float along = std::min(sample, open);
                if (along < 0.5f)
                {
                    break;
                }
                const Vec3 point = Add(from, Scale(direction, along));
                const float meters = along + DistanceBetween(point, to);
                if (meters < best)
                {
                    const RayAnswer answer = co_await CastAwaiter{*this, {point, to, RayGroups::WallsAndDoors}};
                    if (LetsSoundThrough(answer))
                    {
                        best = meters;
                        bestPoint = point;
                        found = true;
                    }
                }
                if (along >= open)
                {
                    break;
                }
            }
        }
        if (found)
        {
            talker->path = {true, bestPoint, best, 1.f, 0.f};
            talker->pathLast = bestPoint;
            talker->pathMiddle = 0.f;
            talker->pathDueMs = m_nowMs + kWayRetestEveryMs;
            ++m_waysFan;
            co_return;
        }
    }

    talker->path.found = false;
    ++m_waysNone;
}

void Acoustics::LogStats()
{
    Logf(LogInfo, "acoustics: room closed %.2f, %.0f m, rings %.1f s, roof over %d of %d directions; wall normals %d from the game, %d guessed; ways round: %d kept, %d their trail, %d my trail, %d fan, %d none",
         m_room.enclosure, m_room.meters, m_room.decaySeconds, m_roofedDirections, kWallDirections, m_normalsFromGame, m_normalsGuessed,
         m_waysKept, m_waysTheirTrail, m_waysMyTrail, m_waysFan, m_waysNone);
    m_normalsFromGame = 0;
    m_normalsGuessed = 0;
    m_waysKept = 0;
    m_waysTheirTrail = 0;
    m_waysMyTrail = 0;
    m_waysFan = 0;
    m_waysNone = 0;
}
} // namespace nv
