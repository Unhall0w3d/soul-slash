#include "creative_thermal_pacer.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <map>
#include <string>
#include <thread>

static std::string read_token(const std::filesystem::path& path) {
    std::ifstream f(path);
    std::string value, extra;
    if (!(f >> value) || (f >> extra)) throw std::runtime_error("thermal sensor read failed");
    return value;
}

static soul_pacing::Temperatures read_temperatures() {
    namespace fs = std::filesystem;
    const fs::path device("/sys/bus/pci/devices/0000:0a:00.0");
    if (read_token(device / "vendor") != "0x1002" || read_token(device / "device") != "0x73bf")
        throw std::runtime_error("AMD identity changed");
    std::map<std::string, double> values;
    int hwmons = 0;
    for (const auto& hw : fs::directory_iterator(device / "hwmon")) {
        ++hwmons;
        for (const auto& sensor : fs::directory_iterator(hw.path())) {
            const auto name = sensor.path().filename().string();
            if (name.rfind("temp", 0) != 0 || name.size() < 11 || name.substr(name.size()-6) != "_label") continue;
            const auto label = read_token(sensor.path());
            if (label != "edge" && label != "junction" && label != "mem") continue;
            const auto raw = read_token(hw.path() / (name.substr(0, name.size()-6) + "_input"));
            size_t used = 0;
            const double value = std::stod(raw, &used) / 1000.0;
            if (used != raw.size() || !values.emplace(label, value).second)
                throw std::runtime_error("ambiguous thermal sensor");
        }
    }
    if (hwmons != 1 || values.size() != 3) throw std::runtime_error("missing thermal sensors");
    return {values.at("edge"), values.at("junction"), values.at("mem")};
}

// Link-time interception of the pinned runtime's synchronous step/tile progress
// call. Byte-loading progress has a different symbol and is not intercepted.
extern "C" void __real__Z15pretty_progressiif(int, int, float);
extern "C" void __wrap__Z15pretty_progressiif(int step, int steps, float seconds) {
    __real__Z15pretty_progressiif(step, steps, seconds);
    const char* enabled = std::getenv("SOUL_RENDER_PACING");
    if (!enabled) return;
    try {
        if (std::string(enabled) != "1") throw std::runtime_error("invalid pacing opt-in");
        static soul_pacing::Pacer pacer;
        auto record = pacer.boundary(step > 0, read_temperatures,
            [] { return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count(); },
            [] { std::this_thread::sleep_for(std::chrono::milliseconds(100)); });
        std::fprintf(stderr, "SOUL_PACING step=%d/%d wait=%.3f total=%.3f edge=%.1f junction=%.1f mem=%.1f\n",
            step, steps, record.waited, record.total, record.temperatures.edge,
            record.temperatures.junction, record.temperatures.memory);
        std::fflush(stderr);
    } catch (const std::exception& e) {
        std::fprintf(stderr, "SOUL_PACING refused: %s\n", e.what());
        std::fflush(stderr);
        // Fail closed, without continuing sampling or writing a success image.
        // Default SIGTERM/SIGINT behavior remains intact even while sleeping.
        std::_Exit(70);
    }
}
