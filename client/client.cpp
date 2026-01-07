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
        checkStickiness = !isEnvDefined("SHUTDOWN_RANDOMLY") || *std::getenv("SHUTDOWN_RANDOMLY") == '0';
    }

    Config(const std::string& url) {
        keepAlive = !isEnvDefined("CLOSE_CONN");
        checkStickiness = !isEnvDefined("SHUTDOWN_RANDOMLY") || *std::getenv("SHUTDOWN_RANDOMLY") == '0';

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
    using Errors = std::map< httplib::Error, int >;

    RespStats responseStatuses;
    Errors errors;

    std::chrono::milliseconds average = 0ms;
    std::chrono::milliseconds min = 0ms;
    std::chrono::milliseconds max = 0ms;
    std::chrono::milliseconds median = 0ms;
    std::chrono::milliseconds p90 = 0ms;


    std::optional< std::string > jsessionid;
    std::map< std::string, int > nodes;
};


std::optional< std::string > getJSESSIONID(const httplib::Headers& headers) {
    for (const auto& [k, v] : headers) {
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

std::optional< std::string > getNode(const std::string& str) {
    std::string::size_type pos = str.find_first_of(".");
    if (pos != std::string::npos) {
        return { str.substr(pos + 1) };
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

    if (val) {
        auto node = getNode(*val);
        if (node) {
            stat.nodes[*node]++;
        }
    }
}

Stat merge(const Stat& s1, const Stat& s2) {
    Stat res;

    for (const auto& [k, v] : s1.responseStatuses) {
        res.responseStatuses[k] = v;
    }

    for (const auto& [k, v] : s2.responseStatuses) {
        res.responseStatuses[k] += v;
    }

    for (const auto& [k, v] : s1.errors) {
        res.errors[k] = v;
    }
    for (const auto& [k, v] : s2.errors) {
        res.errors[k] += v;
    }

    for (const auto& [node, count] : s1.nodes) {
        res.nodes[node] = count;
    }

    for (const auto& [node, count] : s2.nodes) {
        res.nodes[node] += count;
    }

    /* not ideal */
    res.average = (s1.average + s2.average) / 2;
    res.min = std::min(s1.min, s2.min);
    res.max = std::max(s1.max, s2.max);
    res.median = (s1.median + s2.median) / 2;
    res.p90 = std::max(s1.p90, s2.p90);

    return res;
}

void execute(std::promise<Stat> promise, const Config& conf, std::latch& latch) {
    Stat stat;
    httplib::Client client(conf.host);
    client.set_keep_alive(conf.keepAlive);

    std::vector< std::chrono::milliseconds > times;
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

        times.push_back( std::chrono::duration_cast<std::chrono::milliseconds>(end - start) );
        std::this_thread::sleep_for(std::chrono::milliseconds(conf.delay));
    }

    std::sort(times.begin(), times.end());
    std::chrono::milliseconds average = std::accumulate(times.begin(), times.end(), 0ms) / times.size();
    std::chrono::milliseconds median  = times.size() % 2 == 0
                                      ? times[times.size() / 2]
                                      : (times[times.size() / 2] + times[(times.size() + 1) / 2]) / 2;
    // this is probably good enough
    std::chrono::milliseconds p90 = times[times.size() / 10 * 9];

    stat.average = average;
    stat.min = times.front();
    stat.max = times.back();
    stat.median = median;
    stat.p90 = p90;

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
    for (const auto& [k, v] : result.responseStatuses) {
        std::cout << "    " << k << ": " << v << std::endl;
    }
    if (!result.errors.empty()) {
        std::cout << "errors:\n";
        for (const auto& [k, v] : result.errors) {
            std::cout << "    " << httplib::to_string(k) << ": " << v << std::endl;
        }
    }

    if (!result.nodes.empty()) {
        std::cout << "distribution:\n";
        for (const auto& [n, count] : result.nodes) {
            std::cout << "    " << n << ": " << count << std::endl;
        }
    }

    std::cout << "avg: " << result.average
              << " min: " << result.min
              << " max: " << result.max
              << " median: " << result.median
              << " p90-max: " << result.p90
              << std::endl;

    return result.errors.size();
}

