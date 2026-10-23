#include "DamageSystem.h"
#include <cstdlib>
#include <iostream>
#include <limits>
struct Backend : damage::VisualBackend {
    bool allow = true, fail = false;
    int calls = 0;
    std::array<bool, 3> visible{};
    bool supported() const noexcept override { return allow; }
    bool apply(std::size_t i, bool value) noexcept override {
        ++calls;
        if (fail) return false;
        visible[i] = value; return true;
    }
    void restore() noexcept override { visible = {}; }
};
void check(bool pass, const char* what) {
    if (!pass) { std::cerr << what << '\n'; std::exit(1); }
}
int main() {
    Backend backend;
    damage::DamageSystem system(backend);
    damage::Settings settings;
    system.update({true, .20f, .25f, .35f}, settings);
    check(system.state().applied == std::array<bool, 3>{true,true,true}, "threshold equality");
    system.update({true, .20f, .245f, .35f}, settings);
    check(system.state().requested[0] && backend.calls == 3, "hysteresis, no duplicate apply");
    system.update({true, 0, 0, 0}, settings);
    check(backend.visible == std::array<bool,3>{}, "repair restores");
    backend.fail = true;
    system.update({true, 1, 1, 1}, settings);
    check(system.state().requested[0] && !system.state().applied[0], "backend failure not reported as success");
    backend.fail = false;
    system.update({true, 1, 1, 1}, settings);
    check(system.state().applied[0], "failed application retried");
    settings.enabled = false;
    system.update({true, 1, 1, 1}, settings);
    check(!backend.visible[0] && system.state().available, "disable restores but keeps telemetry");
    settings.enabled = true;
    system.update({true, 1, 1, 1}, settings);
    system.update({}, settings);
    check(!system.state().available && !backend.visible[0], "missing vehicle clears");
    system.update({true, std::numeric_limits<float>::quiet_NaN(), 1, 1}, settings);
    check(!system.state().available, "NaN fails closed");
    settings.threshold = {-1, 200, std::numeric_limits<float>::infinity()};
    const auto clean = damage::DamageSystem::sanitize(settings);
    check(clean.threshold == std::array<float,3>{1,100,35}, "invalid settings normalized");
    backend.allow = false;
    system.update({true, 1, 1, 1}, settings);
    check(system.state().requested[0] && !system.state().applied[0], "unsupported backend honest state");
    std::cout << "10 damage-system scenarios passed\n";
}
