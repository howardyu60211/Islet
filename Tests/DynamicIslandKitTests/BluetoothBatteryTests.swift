import Foundation
import Testing
@testable import DynamicIslandKit

struct BluetoothBatteryTests {
    /// 依 macOS 27 `system_profiler SPBluetoothDataType -json` 的結構（位址與名稱是假的）。
    private let json = Data("""
    {
      "SPBluetoothDataType" : [
        {
          "controller_properties" : { "controller_state" : "attrib_on" },
          "device_connected" : [
            { "Howard's AirPods Pro" : {
                "device_address" : "A1:B2:C3:D4:E5:F6",
                "device_batteryLevelCase" : "45%",
                "device_batteryLevelLeft" : "61%",
                "device_batteryLevelRight" : "68%",
                "device_minorType" : "Headphones"
            } },
            { "Magic Mouse" : {
                "device_address" : "11:22:33:44:55:66",
                "device_minorType" : "Mouse"
            } },
            { "Headphones" : {
                "device_address" : "77:88:99:AA:BB:CC",
                "device_batteryLevelMain" : "90 %"
            } }
          ],
          "device_not_connected" : [
            { "Old AirPods" : { "device_address" : "00:00:00:00:00:00", "device_batteryLevelLeft" : "10%" } }
          ]
        }
      ]
    }
    """.utf8)

    @Test func readsLeftRightAndCaseForTheMatchingDevice() {
        let battery = BluetoothBatteryReader.parse(json, address: "a1-b2-c3-d4-e5-f6")
        #expect(battery == HeadphoneBattery(left: 61, right: 68, caseLevel: 45, main: nil))
    }

    @Test func readsSingleBatteryDevices() {
        let battery = BluetoothBatteryReader.parse(json, address: "77-88-99-aa-bb-cc")
        #expect(battery == HeadphoneBattery(main: 90))
    }

    @Test func devicesWithoutBatteryOrNotConnectedReturnNil() {
        #expect(BluetoothBatteryReader.parse(json, address: "11-22-33-44-55-66") == nil)
        #expect(BluetoothBatteryReader.parse(json, address: "00-00-00-00-00-00") == nil)
        #expect(BluetoothBatteryReader.parse(Data("oops".utf8), address: "a1-b2-c3-d4-e5-f6") == nil)
    }

    @Test func addressesAreNormalized() {
        #expect(normalizeBluetoothAddress("A1-B2-C3-D4-E5-F6") == "a1:b2:c3:d4:e5:f6")
        #expect(normalizeBluetoothAddress("a1:b2:c3:d4:e5:f6") == "a1:b2:c3:d4:e5:f6")
    }

    @Test func picksASymbolFromTheDeviceName() {
        #expect(HeadphoneSymbol.name(forDeviceNamed: "Howard's AirPods Pro") == "airpods.pro")
        #expect(HeadphoneSymbol.name(forDeviceNamed: "AirPods Max") == "airpods.max")
        #expect(HeadphoneSymbol.name(forDeviceNamed: "AirPods") == "airpods")
        #expect(HeadphoneSymbol.name(forDeviceNamed: "Beats Studio Pro") == "beats.headphones")
        #expect(HeadphoneSymbol.name(forDeviceNamed: "WH-1000XM5") == "headphones")
    }
}
