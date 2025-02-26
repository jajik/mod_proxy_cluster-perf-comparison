#include "httplib.h"
#include <algorithm>
#include <chrono>
#include <optional>
#include <string>
#include <vector>
#include <thread>
#include <map>
#include <latch>
#include <future>
#include <tuple>

using namespace std::literals::chrono_literals;

inline bool isEnvDefined(const std::string& env) {
    return std::getenv(env.c_str()) != nullptr;
}

struct Config {
    std::string host;
    std::string path;
    int clientCount = 100;
    int reqCount = 1000;
    int delay = 1;
    bool keepAlive = true;
    bool checkStickiness = false;

    Config(const std::string& h, const std::string& p) : host(h), path(p) {
        keepAlive = !isEnvDefined("CLOSE_CONN");
        checkStickiness = !isEnvDefined("SHUTDOWN_RANDOMLY");
    }

    Config(const std::string& url) {
        keepAlive = !isEnvDefined("CLOSE_CONN");
        checkStickiness = !isEnvDefined("SHUTDOWN_RANDOMLY");

        auto pos = url.find_first_of("/");
        if (pos == url.npos) {
            host = url;
            path = "/";            
        } else {
            host = url.substr(0, pos);
            path = url.substr(pos, url.length());
        }
    }
};

struct Stat {
    using RespStats = std::map<int, size_t>;
    using RespTimes = std::tuple< std::chrono::milliseconds /* average */
                                , std::chrono::milliseconds /* min */
                                , std::chrono::milliseconds /* max */
                                >;
    using Errors = std::map< httplib::Error, int >;

    RespStats responseStatuses;
    Errors errors;
    RespTimes times = { 0ms, 0ms, 0ms };

    std::optional< std::string > jsessionid;
};


std::optional< std::string > getJSESSIONID(const httplib::Headers& headers) {
    for (auto [k, v] : headers) {
        if (k == "Set-Cookie") {
            std::string::size_type start = 0, n;

            while ((n = v.find("; ", start)) != std::string::npos) {
                std::string val = v.substr(start, n);

                if (val.starts_with("JSESSIONID=")) {
                    return { val.substr(11) };
                }
                start = n + 2;
            }

            std::string val = v.substr(start);
            if (val.starts_with("JSESSIONID")) {
                return { val.substr(11) };
            }
        }
    }

    return std::nullopt;
}

void processResult(const httplib::Result& res, Stat& stat, bool checkStickiness) {
    if (res) {
        stat.responseStatuses[res->status]++;
    } else {
        stat.errors[res.error()]++;
    }

    // We can't get any cookie in case of an error
    if (!res || !checkStickiness) return;

    auto val = getJSESSIONID(res.value().headers);
    if (!stat.jsessionid) {
        stat.jsessionid = val;
    } else if (val && *stat.jsessionid != *val) {
        std::cout << std::chrono::system_clock::now()
                  << "STICKINESS BREAK! Expected: " << *stat.jsessionid
                  << " but got: " << *val << " (in error " << res << ")" << std::endl;
        // We'll record the stickyness break as an additional error by using Error::Success (TODO: not ideal)
        stat.errors[httplib::Error::Success]++;
    }
}

Stat merge(const Stat& s1, const Stat& s2) {
    Stat res;
    for (auto [k, v] : s1.responseStatuses) {
        res.responseStatuses[k] = v;
    }
    for (auto [k, v] : s2.responseStatuses) {
        res.responseStatuses[k] += v;
    }

    for (auto [k, v] : s1.errors) {
        res.errors[k] = v;
    }
    for (auto [k, v] : s2.errors) {
        res.errors[k] += v;
    }

    /* not ideal */
    res.times = { (std::get<0>(s1.times) + std::get<0>(s2.times)) / 2
                , std::get<1>(s1.times) > std::get<1>(s2.times) ? std::get<1>(s2.times) : std::get<1>(s1.times)
                , std::get<2>(s1.times) > std::get<2>(s2.times) ? std::get<2>(s1.times) : std::get<2>(s2.times)
                };

    return res;
}

void execute(std::promise<Stat> promise, const Config& conf, std::latch& latch) {
    Stat stat;
    httplib::Client client(conf.host);
    client.set_keep_alive(conf.keepAlive);

    std::chrono::milliseconds min = 0ms, max = 0ms, avg = 0ms, tmp = 0ms;
    std::string cookie;

    latch.count_down();
    latch.wait();
    for (int i = 0; i < conf.reqCount; i++) {
        const auto start{std::chrono::steady_clock::now()};

        if (stat.jsessionid) {
            cookie = "JSESSIONID=";
            cookie.append(*stat.jsessionid);
        }

        auto res = stat.jsessionid ? client.Get(conf.path, { { "Cookie", cookie } }) : client.Get(conf.path);
        processResult(res, stat, conf.checkStickiness);
        const auto end{std::chrono::steady_clock::now()};

        tmp = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);
        min = min > tmp ? tmp : min;
        max = tmp > max ? tmp : max;
        avg += tmp;

        std::this_thread::sleep_for(std::chrono::milliseconds(conf.delay));
    }

    stat.times = { avg / conf.reqCount, min, max };

    promise.set_value(stat);
    client.stop();
}

void printParams(const Config& conf) {
    std::cout << "url: " << conf.host + conf.path << " clients: " << conf.clientCount << " requests: "
        << conf.reqCount << " delay: " << conf.delay << std::endl;
}


int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cout << "Missing arguments, at least one is required." << std::endl;
        return 1;
    }

    std::string arg(argv[1]);
    if ("--help" == arg || "-h" == arg) {
        std::cout << "usage: ./client <url> <client count> <request count per client> <delay between requests>"
                  << " (default <url> 10 1000 1)\n"
                  << "    by defining env variable CLOSE_CONN, connections in between requests will be closed"
                  << std::endl;
        return 0;
    }

    Config conf(arg);

    if (argc > 2)
        conf.clientCount = atoi(argv[2]);
    if (argc > 3)
        conf.reqCount = atoi(argv[3]);
    if (argc > 4)
        conf.delay = atoi(argv[4]);

    printParams(conf);

    std::latch latch(conf.clientCount);
    std::vector<std::thread> clients;
    std::vector<std::future<Stat>> results;

    for (int i = 0; i < conf.clientCount; i++) {
        std::promise<Stat> promise;
        results.push_back(promise.get_future());
        clients.emplace_back(execute, std::move(promise), conf, std::ref(latch));
    }

    Stat result;
    for (auto& s : results) {
        result = merge(result, s.get());
    }

    for (int i = 0; i < conf.clientCount; i++) {
        clients[i].join();
    }

    std::cout << "statuses:\n";
    for (auto& [k, v] : result.responseStatuses) {
        std::cout << "    " << k << ": " << v << std::endl;
    }
    if (!result.errors.empty()) {
        std::cout << "errors:\n";
        for (auto& [k, v] : result.errors) {
            std::cout << "    " << httplib::to_string(k) << ": " << v << std::endl;
        }
    }

    std::cout << "avg: " << std::get<0>(result.times) << " min: " << std::get<1>(result.times)
              << " max: " << std::get<2>(result.times) << std::endl;

    return result.errors.size();
}

