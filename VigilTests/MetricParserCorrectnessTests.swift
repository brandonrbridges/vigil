import XCTest
@testable import Vigil

final class MetricParserCorrectnessTests: XCTestCase {

    // MARK: - CPU Parsing

    func testCPUUsageExtraction() {
        let top = "%Cpu(s):  6.4 us,  2.1 sy,  0.0 ni, 90.3 id,  0.2 wa,  0.0 hi,  1.0 si,  0.0 st"
        let uptime = "load average: 1.72, 3.78, 0.00"
        let result = MetricParser.parseCPU(from: top, uptimeOutput: uptime)

        XCTAssertEqual(result.usagePercent, 9.7, accuracy: 0.1) // 100 - 90.3
        XCTAssertEqual(result.loadAverage.one, 1.72, accuracy: 0.01)
        XCTAssertEqual(result.loadAverage.five, 3.78, accuracy: 0.01)
        XCTAssertEqual(result.loadAverage.fifteen, 0.00, accuracy: 0.01)
    }

    func testCPUParsingWithEmptyInput() {
        let result = MetricParser.parseCPU(from: "", uptimeOutput: "")
        XCTAssertEqual(result.usagePercent, 0)
        XCTAssertEqual(result.loadAverage.one, 0)
    }

    func testCPUParsingClampsTo100() {
        // Edge case: negative idle (shouldn't happen but let's be safe)
        let top = "%Cpu(s):  0.0 id"
        let result = MetricParser.parseCPU(from: top, uptimeOutput: "")
        XCTAssertEqual(result.usagePercent, 100.0)
    }

    // MARK: - Memory Parsing

    func testMemoryParsing() {
        let free = """
                      total        used        free      shared  buff/cache   available
        Mem:          64216       10867        6832        1234       31416       53348
        Swap:          2048           0        2048
        """
        let result = MetricParser.parseMemory(from: free)

        XCTAssertEqual(result.totalMB, 64216)
        XCTAssertEqual(result.usedMB, 10867)
        XCTAssertEqual(result.freeMB, 6832)
        XCTAssertEqual(result.cachedMB, 31416)
    }

    func testMemoryParsingEmptyInput() {
        let result = MetricParser.parseMemory(from: "")
        XCTAssertEqual(result.totalMB, 0)
    }

    func testMemoryUsagePercent() {
        let mem = MemoryMetrics(totalMB: 1000, usedMB: 250, cachedMB: 500, freeMB: 250)
        XCTAssertEqual(mem.usagePercent, 25.0, accuracy: 0.1)
    }

    // MARK: - Disk Parsing

    func testDiskParsing() {
        let df = """
        Filesystem     1M-blocks   Used Available Use% Mounted on
        /dev/sda1         436512 130812    283402  32% /
        tmpfs              3200        0     3200   0% /dev/shm
        /dev/sdb1         102400  45678     56722  45% /data
        """
        let result = MetricParser.parseDisk(from: df)

        // tmpfs should be filtered out
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].mountPoint, "/")
        XCTAssertEqual(result[0].sizeMB, 436512)
        XCTAssertEqual(result[1].mountPoint, "/data")
    }

    func testDiskFiltersSnapMounts() {
        let df = """
        Filesystem     1M-blocks   Used Available Use% Mounted on
        /dev/sda1         436512 130812    283402  32% /
        /dev/loop0            64     64         0 100% /snap/core/12345
        """
        let result = MetricParser.parseDisk(from: df)
        XCTAssertEqual(result.count, 1) // /snap filtered
    }

    // MARK: - Network Parsing

    func testNetworkParsing() {
        let ip = """
        2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP>
            RX: bytes  packets  errors
            1095291842560  987654321  0
            TX: bytes  packets  errors
            350784614400   876543210  0
        """
        let result = MetricParser.parseNetwork(from: ip, ssOutput: "13\n")

        XCTAssertEqual(result.bytesIn, 1095291842560)
        XCTAssertEqual(result.bytesOut, 350784614400)
        XCTAssertEqual(result.activeConnections, 12) // 13 - 1 (header)
    }

    // MARK: - Services Parsing

    func testServicesParsing() {
        let services = """
        apache2.service                   loaded active running The Apache HTTP Server
        docker.service                    loaded active running Docker Application Container Engine
        systemd-journald.service          loaded active running Journal Service
        """
        let result = MetricParser.parseServices(from: services)

        // systemd- prefixed services are filtered
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "apache2")
        XCTAssertEqual(result[0].state, .active)
        XCTAssertEqual(result[1].name, "docker")
    }

    // MARK: - System Info Parsing

    func testSystemInfoParsing() {
        let result = MetricParser.parseSystemInfo(
            from: "my-server\n",
            unameOutput: "Linux 5.15.0-91-generic x86_64\n",
            uptimeOutput: "up 97 days, 9 hours, 23 minutes\n"
        )

        XCTAssertEqual(result.hostname, "my-server")
        XCTAssertEqual(result.os, "Linux")
        XCTAssertEqual(result.kernel, "x86_64")
        XCTAssertEqual(result.uptime, "97 days, 9 hours, 23 minutes")
    }

    func testUptimeParsingFromRegularUptime() {
        // Regular uptime output: " 21:58:24 up 97 days,  9:23,  6 users,  load average: 1.72, 3.78, 3.28"
        let result = MetricParser.parseSystemInfo(
            from: "host\n",
            unameOutput: "Linux 5.15.0 x86_64\n",
            uptimeOutput: " 21:58:24 up 97 days,  9:23,  6 users,  load average: 1.72, 3.78, 3.28\n"
        )

        XCTAssertFalse(result.uptime.contains("load average"))
        XCTAssertTrue(result.uptime.contains("97 days"))
    }

    // MARK: - Server Model

    func testServerSanitizesHost() {
        let server = Server(host: "  192.168.1.1  ", username: "  root  ")
        XCTAssertEqual(server.host, "192.168.1.1")
        XCTAssertEqual(server.username, "root")
    }

    func testServerClampsPort() {
        let serverLow = Server(host: "host", port: -1)
        XCTAssertEqual(serverLow.port, 1)

        let serverHigh = Server(host: "host", port: 99999)
        XCTAssertEqual(serverHigh.port, 65535)

        let serverNormal = Server(host: "host", port: 2222)
        XCTAssertEqual(serverNormal.port, 2222)
    }

    // MARK: - Docker Container Model

    func testDockerContainerMemoryPercent() {
        let container = DockerContainer(
            id: "abc123", name: "web", image: "nginx:latest",
            status: "Up 5 hours", state: .running, ports: "80/tcp",
            cpuPercent: 2.5, memoryUsageMB: 256, memoryLimitMB: 1024
        )
        XCTAssertEqual(container.memoryPercent, 25.0, accuracy: 0.1)
    }

    func testDockerContainerZeroMemoryLimit() {
        let container = DockerContainer(
            id: "abc123", name: "web", image: "nginx:latest",
            status: "Up", state: .running, ports: "",
            cpuPercent: 0, memoryUsageMB: 0, memoryLimitMB: 0
        )
        XCTAssertEqual(container.memoryPercent, 0)
    }
}
