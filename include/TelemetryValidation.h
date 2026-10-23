#pragma once
#include <string_view>
namespace damage {
// SPF 1.2.5 returns uppercase ATS; raw SCS SDK uses lowercase ats.
inline bool isAts(std::string_view id) noexcept { return id == "ATS" || id == "ats"; }
}
