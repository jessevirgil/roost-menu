import Foundation

/// Fake devices for `RoostMenu --demo`, so the UI can be checked without Google credentials.
enum DemoData {
    static let devices: [SDMDevice] = {
        let json = """
        {"devices":[
         {"name":"enterprises/demo/devices/t1","type":"sdm.devices.types.THERMOSTAT",
          "traits":{
           "sdm.devices.traits.Info":{"customName":"Hallway"},
           "sdm.devices.traits.Connectivity":{"status":"ONLINE"},
           "sdm.devices.traits.Settings":{"temperatureScale":"FAHRENHEIT"},
           "sdm.devices.traits.Temperature":{"ambientTemperatureCelsius":21.4},
           "sdm.devices.traits.Humidity":{"ambientHumidityPercent":42},
           "sdm.devices.traits.ThermostatMode":{"mode":"HEAT","availableModes":["HEAT","COOL","HEATCOOL","OFF"]},
           "sdm.devices.traits.ThermostatEco":{"mode":"OFF","availableModes":["OFF","MANUAL_ECO"]},
           "sdm.devices.traits.ThermostatHvac":{"status":"HEATING"},
           "sdm.devices.traits.ThermostatTemperatureSetpoint":{"heatCelsius":22.0}}},
         {"name":"enterprises/demo/devices/d1","type":"sdm.devices.types.DOORBELL",
          "traits":{"sdm.devices.traits.Info":{"customName":"Front Door"},
           "sdm.devices.traits.Connectivity":{"status":"ONLINE"},
           "sdm.devices.traits.CameraLiveStream":{"supportedProtocols":["WEB_RTC"]}}},
         {"name":"enterprises/demo/devices/c1","type":"sdm.devices.types.CAMERA",
          "traits":{"sdm.devices.traits.Info":{"customName":"Living Room"},
           "sdm.devices.traits.Connectivity":{"status":"ONLINE"},
           "sdm.devices.traits.CameraLiveStream":{"supportedProtocols":["WEB_RTC"]}}},
         {"name":"enterprises/demo/devices/c2","type":"sdm.devices.types.CAMERA",
          "traits":{"sdm.devices.traits.Info":{"customName":"Garden"},
           "sdm.devices.traits.Connectivity":{"status":"OFFLINE"},
           "sdm.devices.traits.CameraLiveStream":{"supportedProtocols":["WEB_RTC"]}}}
        ]}
        """
        return (try? SDMDevice.decodeList(Data(json.utf8))) ?? []
    }()
}
