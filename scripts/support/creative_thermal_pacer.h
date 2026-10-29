#ifndef SOUL_CREATIVE_THERMAL_PACER_H
#define SOUL_CREATIVE_THERMAL_PACER_H
#include <cmath>
#include <functional>
#include <stdexcept>

namespace soul_pacing {
struct Temperatures { double edge, junction, memory; };
struct Record { double waited, total; Temperatures temperatures; };

// Supplemental duty-cycle control, never a replacement for the external guard.
// No model state, sampling parameters, clocks or power settings are changed.
class Pacer {
    double total_ = 0;
public:
    Record boundary(bool completed, const std::function<Temperatures()>& read,
                    const std::function<double()>& now,
                    const std::function<void()>& sleep_tick) {
        const double start = now();
        bool cooling = false;
        for (;;) {
            const auto t = read();
            for (double v : {t.edge, t.junction, t.memory})
                if (!std::isfinite(v) || v < 0 || v > 150)
                    throw std::runtime_error("invalid thermal sensor");
            if (t.edge >= 90 || t.junction >= 100 || t.memory >= 90)
                throw std::runtime_error("hard thermal bound");
            if (t.edge >= 75 || t.junction >= 85 || t.memory >= 75) cooling = true;
            const double waited = now() - start;
            if (waited < 0 || waited >= 30 || total_ + waited >= 180)
                throw std::runtime_error("pacing wait budget exhausted");
            const bool cooled = t.edge <= 65 && t.junction <= 75 && t.memory <= 70;
            if (waited >= (completed ? 1.0 : 0.0) && (!cooling || cooled)) {
                total_ += waited;
                return {waited, total_, t};
            }
            sleep_tick();
        }
    }
};
}
#endif
