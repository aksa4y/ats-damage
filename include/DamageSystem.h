#pragma once
#include <array>
#include <cstddef>
namespace damage {
constexpr std::size_t PartCount = 3;
struct Settings {
    bool enabled = true;
    std::array<float, PartCount> threshold{25.f, 20.f, 35.f}; // percent
};
struct Sample {
    bool available = false;
    float cabin = 0, chassis = 0, wheels = 0;
};
struct State {
    std::array<float, PartCount> wear{};
    std::array<bool, PartCount> requested{};
    std::array<bool, PartCount> applied{};
    bool available = false;
};
// Contract: called on render thread. restore() must be idempotent.
// apply returns true ONLY after a real material change on the player's truck.
class VisualBackend {
public:
    virtual ~VisualBackend() = default;
    virtual bool supported() const noexcept = 0;
    virtual bool apply(std::size_t part, bool damaged) noexcept = 0;
    virtual void restore() noexcept = 0;
};
class UnavailableBackend final : public VisualBackend {
public:
    bool supported() const noexcept override { return false; }
    bool apply(std::size_t, bool) noexcept override { return false; }
    void restore() noexcept override {}
};
class DamageSystem {
public:
    explicit DamageSystem(VisualBackend& backend) : backend_(backend) {}
    void update(const Sample&, const Settings&) noexcept;
    void reset() noexcept;
    const State& state() const noexcept { return state_; }
    static Settings sanitize(Settings) noexcept;
private:
    VisualBackend& backend_;
    State state_{};
};
}
