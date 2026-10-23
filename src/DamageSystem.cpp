#include "DamageSystem.h"
#include <algorithm>
#include <cmath>
namespace damage {
Settings DamageSystem::sanitize(Settings settings) noexcept {
    const Settings defaults;
    for (std::size_t i = 0; i < PartCount; ++i)
        settings.threshold[i] = std::isfinite(settings.threshold[i])
            ? std::clamp(settings.threshold[i], 1.f, 100.f) : defaults.threshold[i];
    return settings;
}
void DamageSystem::reset() noexcept {
    backend_.restore();
    state_ = {};
}
void DamageSystem::update(const Sample& sample, const Settings& raw) noexcept {
    const auto settings = sanitize(raw);
    if (!sample.available || !std::isfinite(sample.cabin) ||
        !std::isfinite(sample.chassis) || !std::isfinite(sample.wheels)) {
        reset();
        return;
    }
    state_.available = true;
    // These are deliberate approximations, NOT SDK bumper/headlight channels.
    state_.wear = {std::clamp(sample.chassis, 0.f, 1.f),
                   std::clamp(sample.cabin, 0.f, 1.f),
                   std::clamp(sample.wheels, 0.f, 1.f)};
    if (!settings.enabled) {
        backend_.restore();
        state_.requested = {};
        state_.applied = {};
        return;
    }
    for (std::size_t i = 0; i < PartCount; ++i) {
        const float percent = state_.wear[i] * 100.f;
        // One percentage point of hysteresis avoids oscillation at the boundary.
        if (percent >= settings.threshold[i]) state_.requested[i] = true;
        else if (percent <= std::max(0.f, settings.threshold[i] - 1.f))
            state_.requested[i] = false;
        if (backend_.supported() && state_.requested[i] != state_.applied[i]) {
            if (backend_.apply(i, state_.requested[i]))
                state_.applied[i] = state_.requested[i];
        }
    }
    if (!backend_.supported()) {
        backend_.restore();
        state_.applied = {};
    }
}
}
