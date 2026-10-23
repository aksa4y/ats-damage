#include "UI.h"
#include <cstdio>
namespace damage {
bool drawPanel(SPF_UI_API* ui, Settings& settings, const State& state) {
    if (!ui) return false;
    ui->UI_TextWrapped("Визуальный адаптер не реализован. Внешний вид грузовика пока не изменяется.");
    ui->UI_Checkbox("Расчёт повреждений", &settings.enabled);
    constexpr const char* labels[] = {"Порог повреждения бампера (%)",
        "Порог повреждения фар (%)", "Порог повреждения колёс (%)"};
    constexpr const char* names[] = {"Бампер ← шасси", "Фары ← кабина", "Колёса ← средний износ"};
    for (std::size_t i = 0; i < PartCount; ++i) {
        ui->UI_SliderFloat(labels[i], &settings.threshold[i], 1.f, 100.f,
                           "%.0f %%", SPF_SLIDER_FLAG_ALWAYS_CLAMP);
        char text[256];
        if (!state.available) std::snprintf(text, sizeof(text), "%s: нет данных", names[i]);
        else std::snprintf(text, sizeof(text), "%s: %.1f%% — %s", names[i],
            static_cast<double>(state.wear[i] * 100.f),
            state.requested[i] ? "порог достигнут" : "ниже порога");
        ui->UI_Text(text);
    }
    ui->UI_Separator();
    ui->UI_TextWrapped("Бампер и фары оцениваются приблизительно. Данные отдельных шин недоступны. Пороги не изменяют физический урон.");
    if (ui->UI_Button("Сбросить пороги", 0, 0)) settings = Settings{};
    return ui->UI_Button("Сохранить настройки", 0, 0);
}
}
