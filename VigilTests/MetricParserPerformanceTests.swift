import XCTest
@testable import Vigil

final class MetricParserPerformanceTests: XCTestCase {

    // MARK: - Test Data (realistic output from Linux servers)

    static let sampleTopOutput = """
    top - 21:58:24 up 97 days,  9:23,  6 users,  load average: 1.72, 3.78, 0.00
    Tasks: 245 total,   1 running, 244 sleeping,   0 stopped,   0 zombie
    %Cpu(s):  6.4 us,  2.1 sy,  0.0 ni, 90.3 id,  0.2 wa,  0.0 hi,  1.0 si,  0.0 st
    MiB Mem :  64216.0 total,   6832.4 free,  10867.2 used,  49315.8 buff/cache
    MiB Swap:   2048.0 total,   2048.0 free,      0.0 used.  53348.8 avail Mem
    """

    static let sampleFreeOutput = """
                  total        used        free      shared  buff/cache   available
    Mem:          64216       10867        6832        1234       31416       53348
    Swap:          2048           0        2048
    """

    static let sampleDfOutput = """
    Filesystem     1M-blocks   Used Available Use% Mounted on
    /dev/sda1         436512 130812    283402  32% /
    /dev/sda15           253     12       241   5% /boot/efi
    tmpfs              3200        0     3200   0% /dev/shm
    /dev/sdb1         102400  45678     56722  45% /data
    """

    static let sampleIpOutput = """
    1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
        link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
        RX: bytes  packets  errors  dropped overrun mcast
        12345678   98765    0       0       0       0
        TX: bytes  packets  errors  dropped carrier collsns
        12345678   98765    0       0       0       0
    2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP mode DEFAULT group default qlen 1000
        link/ether 96:00:02:a7:b3:15 brd ff:ff:ff:ff:ff:ff
        RX: bytes  packets  errors  dropped overrun mcast
        1095291842560  987654321  0  0  0  0
        TX: bytes  packets  errors  dropped carrier collsns
        350784614400   876543210  0  0  0  0
    """

    static let sampleSsOutput = "13\n"

    static let sampleServicesOutput = """
    accounts-daemon.service           loaded active running Accounts Service
    apache2.service                   loaded active running The Apache HTTP Server
    atd.service                       loaded active running Deferred execution scheduler
    containerd.service                loaded active running containerd container runtime
    cron.service                      loaded active running Regular background program processing daemon
    docker.service                    loaded active running Docker Application Container Engine
    getty@tty1.service                loaded active running Getty on tty1
    networkd-dispatcher.service       loaded active running Dispatcher daemon for systemd-networkd
    nginx.service                     loaded active running A high performance web server
    postgresql@14-main.service        loaded active running PostgreSQL Cluster 14-main
    redis-server.service              loaded active running Advanced key-value store
    sshd.service                      loaded active running OpenBSD Secure Shell server
    systemd-journald.service          loaded active running Journal Service
    systemd-logind.service            loaded active running User Login Management
    systemd-networkd.service          loaded active running Network Configuration
    systemd-resolved.service          loaded active running Network Name Resolution
    systemd-timesyncd.service         loaded active running Network Time Synchronization
    systemd-udevd.service             loaded active running Rule-based Manager for Device Events
    unattended-upgrades.service       loaded active running Unattended Upgrades Shutdown
    ufw.service                       loaded active running Uncomplicated firewall
    """

    static let sampleHostnameOutput = "Ubuntu-2204-jammy-amd64-base\n"
    static let sampleUnameOutput = "Linux 5.15.0-91-generic x86_64\n"
    static let sampleUptimeOutput = "up 97 days, 9 hours, 23 minutes\n"

    // MARK: - Performance: CPU Parsing

    func testCPUParsingPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = MetricParser.parseCPU(from: Self.sampleTopOutput, uptimeOutput: Self.sampleUptimeOutput)
            }
        }
    }

    // MARK: - Performance: Memory Parsing

    func testMemoryParsingPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = MetricParser.parseMemory(from: Self.sampleFreeOutput)
            }
        }
    }

    // MARK: - Performance: Disk Parsing

    func testDiskParsingPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = MetricParser.parseDisk(from: Self.sampleDfOutput)
            }
        }
    }

    // MARK: - Performance: Network Parsing

    func testNetworkParsingPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = MetricParser.parseNetwork(from: Self.sampleIpOutput, ssOutput: Self.sampleSsOutput)
            }
        }
    }

    // MARK: - Performance: Services Parsing

    func testServicesParsingPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = MetricParser.parseServices(from: Self.sampleServicesOutput)
            }
        }
    }

    // MARK: - Performance: System Info Parsing

    func testSystemInfoParsingPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = MetricParser.parseSystemInfo(
                    from: Self.sampleHostnameOutput,
                    unameOutput: Self.sampleUnameOutput,
                    uptimeOutput: Self.sampleUptimeOutput
                )
            }
        }
    }

    // MARK: - Performance: Full Metrics Parse (all parsers combined)

    func testFullMetricsParsePerformance() {
        measure {
            for _ in 0..<500 {
                _ = MetricParser.parseCPU(from: Self.sampleTopOutput, uptimeOutput: Self.sampleUptimeOutput)
                _ = MetricParser.parseMemory(from: Self.sampleFreeOutput)
                _ = MetricParser.parseDisk(from: Self.sampleDfOutput)
                _ = MetricParser.parseNetwork(from: Self.sampleIpOutput, ssOutput: Self.sampleSsOutput)
                _ = MetricParser.parseServices(from: Self.sampleServicesOutput)
                _ = MetricParser.parseSystemInfo(
                    from: Self.sampleHostnameOutput,
                    unameOutput: Self.sampleUnameOutput,
                    uptimeOutput: Self.sampleUptimeOutput
                )
            }
        }
    }

    // MARK: - Performance: Section Splitting (the marker-based parser)

    func testSectionSplittingPerformance() {
        // Simulate the combined output from a single SSH call
        let combinedOutput = """
        ---TOP---
        \(Self.sampleTopOutput)
        ---FREE---
        \(Self.sampleFreeOutput)
        ---DF---
        \(Self.sampleDfOutput)
        ---IP---
        \(Self.sampleIpOutput)
        ---SS---
        \(Self.sampleSsOutput)
        ---SERVICES---
        \(Self.sampleServicesOutput)
        ---HOSTNAME---
        \(Self.sampleHostnameOutput)
        ---UNAME---
        \(Self.sampleUnameOutput)
        ---UPTIME---
        \(Self.sampleUptimeOutput)
        """

        measure {
            for _ in 0..<1000 {
                var sections: [String: String] = [:]
                var currentKey: String?
                var currentLines: [String] = []

                for line in combinedOutput.components(separatedBy: "\n") {
                    if line.hasPrefix("---") && line.hasSuffix("---") {
                        if let key = currentKey {
                            sections[key] = currentLines.joined(separator: "\n")
                        }
                        currentKey = String(line.dropFirst(3).dropLast(3))
                        currentLines = []
                    } else {
                        currentLines.append(line)
                    }
                }
                if let key = currentKey {
                    sections[key] = currentLines.joined(separator: "\n")
                }
                _ = sections
            }
        }
    }
}
