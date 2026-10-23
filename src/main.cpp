#include "DamageSystem.h"
#include "UI.h"
#include <SPF/SPF_API/SPF_Plugin.h>
#include <SPF/SPF_API/SPF_Manifest_API.h>
#include <SPF/SPF_API/SPF_Config_API.h>
#include <SPF/SPF_API/SPF_Telemetry_API.h>
#include <SPF/SPF_API/SPF_KeyBinds_API.h>
#include <cstring>
namespace {
constexpr char Name[] = "ATSDamage";
constexpr const char* Keys[] = {"settings.bumper", "settings.lights", "settings.wheels"};
const SPF_Core_API* core = nullptr;
SPF_Config_Handle* config = nullptr;
SPF_Telemetry_Handle* telemetry = nullptr;
SPF_Window_Handle* window = nullptr;
damage::UnavailableBackend backend;
damage::DamageSystem system(backend);
damage::Settings settings;
char truckId[SPF_TELEMETRY_ID_MAX_SIZE]{};
void load(const SPF_Load_API*) {}
void activated(const SPF_Core_API* api) {
    core = api;
    if (!core) return;
    if (core->config) {
        config = core->config->Cfg_GetContext(Name);
        if (config) {
            settings.enabled = core->config->Cfg_GetBool(config, "settings.enabled", true);
            for (std::size_t i = 0; i < damage::PartCount; ++i)
                settings.threshold[i] = static_cast<float>(core->config->Cfg_GetFloat(config, Keys[i], settings.threshold[i]));
            settings = damage::DamageSystem::sanitize(settings);
        }
    }
    if (core->telemetry) telemetry = core->telemetry->Tel_GetContext(Name);
    if (core->keybinds) {
        auto* handle = core->keybinds->Kbind_GetContext(Name);
        if (handle) core->keybinds->Kbind_Register(handle, "Panel.toggle", []() {
            if (core && core->ui && window)
                core->ui->UI_SetVisibility(window, !core->ui->UI_IsVisible(window));
        });
    }
}
void update() {
    if (!core || !core->telemetry || !telemetry) { system.reset(); return; }
    SPF_GameState game{};
    SPF_TruckConstants constants{};
    SPF_TruckData data{};
    auto* api = core->telemetry;
    api->Tel_GetGameState(telemetry, &game, sizeof(game));
    api->Tel_GetTruckConstants(telemetry, &constants, sizeof(constants));
    api->Tel_GetTruckData(telemetry, &data, sizeof(data));
    if (std::memcmp(truckId, constants.id, sizeof(truckId)) != 0) {
        system.reset();
        std::memcpy(truckId, constants.id, sizeof(truckId));
    }
    const bool available = std::strncmp(game.game_id, "ats", sizeof(game.game_id)) == 0
        && constants.id[0] != '\0' && !game.paused;
    system.update({available, data.wear_cabin, data.wear_chassis, data.wear_wheels}, settings);
}
void draw(SPF_UI_API* ui, void*) {
    if (!damage::drawPanel(ui, settings, system.state()) || !core || !core->config || !config) return;
    settings = damage::DamageSystem::sanitize(settings);
    core->config->Cfg_SetBool(config, "settings.enabled", settings.enabled);
    for (std::size_t i = 0; i < damage::PartCount; ++i)
        core->config->Cfg_SetFloat(config, Keys[i], settings.threshold[i]);
    core->config->Cfg_Save(config);
}
void registerUI(SPF_UI_API* ui) {
    if (!ui) return;
    ui->UI_RegisterDrawCallback(Name, "Panel", draw, nullptr);
    window = ui->UI_GetWindowHandle(Name, "Panel");
}
void unload() {
    system.reset();
    // SPF owns handles and removes registrations during plugin teardown.
    core = nullptr; config = nullptr; telemetry = nullptr; window = nullptr;
    std::memset(truckId, 0, sizeof(truckId));
    settings = {};
}
void manifest(SPF_Manifest_Builder_Handle* h, const SPF_Manifest_Builder_API* api) {
    api->Info_SetName(h, Name);
    api->Info_SetVersion(h, "0.1.0");
    api->Info_SetMinFrameworkVersion(h, "1.2.5");
    api->Info_SetAuthor(h, "ats-damage contributors");
    api->Info_SetGithubUrl(h, "https://github.com/aksa4y/ats-damage");
    api->Info_SetDescriptionLiteral(h, "Панель порогов повреждений. Визуальный адаптер не реализован.");
    api->Policy_SetAllowUserConfig(h, true);
    api->Policy_AddConfigurableSystem(h, "settings");
    api->Policy_AddConfigurableSystem(h, "ui");
    api->Defaults_SetLocalization(h, "ru");
    api->Settings_SetJson(h, R"({"enabled":true,"bumper":25,"lights":20,"wheels":35})");
    api->Defaults_AddWindow(h, "Panel", true, true, 30, 60, 470, 370, false, false);
    api->Meta_AddWindow(h, "Panel", "Повреждения грузовика", "Пороги визуальных эффектов");
    api->Defaults_AddKeybind(h, "Panel", "toggle", "keyboard", "KEY_F7", "always");
    api->Meta_AddKeybind(h, "Panel", "toggle", "Показать панель повреждений", "Открыть или скрыть панель");
}
}
extern "C" SPF_PLUGIN_EXPORT bool SPF_GetManifestAPI(SPF_Manifest_API* out) {
    if (!out) return false;
    out->BuildManifest = manifest;
    return true;
}
extern "C" SPF_PLUGIN_EXPORT bool SPF_GetPlugin(SPF_Plugin_Exports* out) {
    if (!out) return false;
    *out = {};
    out->OnLoad = load; out->OnActivated = activated;
    out->OnUnload = unload; out->OnUpdate = update; out->OnRegisterUI = registerUI;
    return true;
}
