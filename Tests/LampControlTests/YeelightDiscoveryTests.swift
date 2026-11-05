import XCTest
@testable import LampControl

final class YeelightDiscoveryTests: XCTestCase {
    private let reply = [
        "HTTP/1.1 200 OK",
        "Cache-Control: max-age=3600",
        "Date: ",
        "Ext: ",
        "Location: yeelight://192.168.1.77:55443",
        "Server: POSIX UPnP/1.0 YGLC/1",
        "id: 0x00000000abcd1234",
        "model: color4",
        "fw_ver: 24",
        "support: get_prop set_default set_power toggle set_bright start_cf stop_cf set_scene",
        "power: on",
        "bright: 100",
        "color_mode: 2",
        "ct: 4000",
        "rgb: 16711680",
        "hue: 359",
        "sat: 100",
        "name: ",
        "", ""
    ].joined(separator: "\r\n")

    func testParsesRealisticReply() throws {
        let bulb = try XCTUnwrap(YeelightDiscovery.parse(reply, senderHost: "192.168.1.77"))
        XCTAssertEqual(bulb.id, "0x00000000abcd1234")
        XCTAssertEqual(bulb.host, "192.168.1.77")
        XCTAssertEqual(bulb.port, 55443)
        XCTAssertEqual(bulb.model, "color4")
        XCTAssertEqual(bulb.firmware, "24")
        XCTAssertEqual(bulb.name, "")
        XCTAssertEqual(bulb.displayName, "Yeelight color4")
        XCTAssertEqual(bulb.address, "192.168.1.77:55443")
    }

    func testLFOnlyLineEndingsWork() throws {
        let lf = reply.replacingOccurrences(of: "\r\n", with: "\n")
        XCTAssertEqual(YeelightDiscovery.parse(lf)?.id, "0x00000000abcd1234")
    }

    func testLocationWinsOverSenderHostAndCustomPortIsRead() throws {
        let message = "HTTP/1.1 200 OK\r\nLocation: yeelight://10.0.0.7:12345\r\nid: 0xABCDEF\r\n\r\n"
        let bulb = try XCTUnwrap(YeelightDiscovery.parse(message, senderHost: "192.168.1.1"))
        XCTAssertEqual(bulb.host, "10.0.0.7")
        XCTAssertEqual(bulb.port, 12345)
        XCTAssertEqual(bulb.id, "0xabcdef", "device id is lowercased")
    }

    func testFallsBackToSenderHostWithoutLocation() throws {
        let bulb = try XCTUnwrap(YeelightDiscovery.parse("HTTP/1.1 200 OK\r\nid: 0x1\r\n\r\n", senderHost: "192.168.1.50"))
        XCTAssertEqual(bulb.host, "192.168.1.50")
        XCTAssertEqual(bulb.port, 55443)
    }

    func testNoHostAtAllIsRejected() {
        XCTAssertNil(YeelightDiscovery.parse("HTTP/1.1 200 OK\r\nid: 0x1\r\n\r\n"))
    }

    func testHeaderNamesAreCaseInsensitive() throws {
        let message = "NOTIFY * HTTP/1.1\r\nLOCATION: yeelight://192.168.1.9:55443\r\nID: 0x2\r\nModel: mono\r\nNAME: Bedroom\r\n\r\n"
        let bulb = try XCTUnwrap(YeelightDiscovery.parse(message))
        XCTAssertEqual(bulb.id, "0x2")
        XCTAssertEqual(bulb.model, "mono")
        XCTAssertEqual(bulb.displayName, "Bedroom")
    }

    func testByeByeNotifyIsIgnored() {
        let message = "NOTIFY * HTTP/1.1\r\nNTS: ssdp:byebye\r\nLocation: yeelight://192.168.1.9:55443\r\nid: 0x2\r\n\r\n"
        XCTAssertNil(YeelightDiscovery.parse(message))
    }

    func testOwnLoopedBackSearchIsIgnored() {
        let search = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1982\r\nMAN: \"ssdp:discover\"\r\nST: wifi_bulb\r\n\r\n"
        XCTAssertNil(YeelightDiscovery.parse(search, senderHost: "192.168.1.2"))
    }

    func testGarbageIsRejected() {
        XCTAssertNil(YeelightDiscovery.parse(""))
        XCTAssertNil(YeelightDiscovery.parse("garbage", senderHost: "1.2.3.4"))
        XCTAssertNil(YeelightDiscovery.parse("\r\n\r\n:::\r\n", senderHost: "1.2.3.4"))
        XCTAssertNil(YeelightDiscovery.parse("id:\r\n", senderHost: "1.2.3.4"), "empty id")
    }

    func testNonYeelightLocationFallsBackToSenderHost() throws {
        let message = "HTTP/1.1 200 OK\r\nLocation: http://example.com:80\r\nid: 0x3\r\n\r\n"
        let bulb = try XCTUnwrap(YeelightDiscovery.parse(message, senderHost: "192.168.1.4"))
        XCTAssertEqual(bulb.host, "192.168.1.4")
        XCTAssertEqual(bulb.port, 55443)
    }

    func testDisplayNameFallbacks() {
        let none = YeelightDiscoveredBulb(id: "x", host: "h", port: 1, model: "", name: "", firmware: "")
        XCTAssertEqual(none.displayName, "Yeelight")
    }
}
