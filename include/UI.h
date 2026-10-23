#pragma once
#include "DamageSystem.h"
#include <SPF/SPF_API/SPF_UI_API.h>
namespace damage {
// Returns true when the user explicitly requests persistence.
bool drawPanel(SPF_UI_API*, Settings&, const State&);
}
