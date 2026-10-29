#include "support/creative_thermal_pacer.h"
#include <cassert>
#include <limits>
#include <iostream>
#include <chrono>
#include <thread>
#include <string>
using namespace soul_pacing;
int main(int argc, char** argv) {
    if (argc == 2 && std::string(argv[1]) == "--waiting") {
        Pacer waiting;
        std::cout << "waiting" << std::endl;
        waiting.boundary(true,[]{return Temperatures{76,86,50};},
            []{return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();},
            []{std::this_thread::sleep_for(std::chrono::milliseconds(100));});
        return 1;
    }
    double clock = 0;
    auto now = [&] { return clock; };
    auto tick = [&] { clock += 0.125; };
    auto cool = [] { return Temperatures{40,50,40}; };
    Pacer p;
    assert(p.boundary(false,cool,now,tick).waited == 0);
    assert(p.boundary(true,cool,now,tick).waited == 1);
    int reads = 0;
    auto hysteresis = [&] { ++reads; return reads < 5 ? Temperatures{76,86,50} : (reads < 20 ? Temperatures{70,80,50} : Temperatures{65,75,50}); };
    assert(p.boundary(true,hysteresis,now,tick).waited > 2);
    for (auto t : {Temperatures{90,50,40}, Temperatures{40,100,40}, Temperatures{40,50,90},
                   Temperatures{-1,50,40}, Temperatures{40,std::numeric_limits<double>::quiet_NaN(),40}}) {
        bool rejected = false;
        try { p.boundary(false,[&]{return t;},now,tick); } catch (const std::runtime_error&) { rejected = true; }
        assert(rejected);
    }
    bool missing = false;
    try { p.boundary(false,[]()->Temperatures{throw std::runtime_error("missing");},now,tick); }
    catch (const std::runtime_error&) { missing = true; }
    assert(missing);
    bool timeout = false;
    try { p.boundary(true,[]{return Temperatures{76,86,50};},now,tick); }
    catch (const std::runtime_error&) { timeout = true; }
    assert(timeout);
    Pacer cumulative;
    for (int i=0;i<179;++i) cumulative.boundary(true,cool,now,tick);
    bool exhausted = false;
    try { cumulative.boundary(true,cool,now,tick); } catch (const std::runtime_error&) { exhausted = true; }
    assert(exhausted);
    std::cout << "Pacer deterministic checks passed\n";
}
