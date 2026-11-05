import Foundation

/// A latitude / longitude pair destined for a lead's `latitude` / `longitude` columns.
struct LeadCoordinate: Equatable {
    let latitude: Double
    let longitude: Double
}

/// Pure rules for where a Spark & Ray lead's map pin comes from.
///
/// A Spark rep fills the form at a desk or in the car, not at the customer's plant, so the device GPS
/// must not decide where the lead lands on the map. When a Google address was PICKED, its coordinates
/// win and the device fix is ignored; with no picked address everything behaves as before (device GPS).
/// Every other tenant is unaffected (`isSpark == false` always falls through to the device fix).
enum LeadAddressCoordinates {
    /// Valid, real coordinates: finite, in range, and not the (0, 0) "no fix" placeholder.
    static func isUsable(latitude: Double?, longitude: Double?) -> Bool {
        guard let lat = latitude, let lon = longitude, lat.isFinite, lon.isFinite else { return false }
        guard abs(lat) <= 90, abs(lon) <= 180 else { return false }
        return !(lat == 0 && lon == 0)
    }

    /// The coordinates carried by a picked place, or nil when it has none / they are unusable.
    static func coordinate(from detail: CRMPlaceDetail) -> LeadCoordinate? {
        guard isUsable(latitude: detail.latitude, longitude: detail.longitude),
              let lat = detail.latitude, let lon = detail.longitude else { return nil }
        return LeadCoordinate(latitude: lat, longitude: lon)
    }

    /// The coordinates that override the device fix: the picked address's, for Spark only; nil otherwise
    /// (then the device GPS fix is used exactly as before).
    static func pickedOverride(isSpark: Bool, picked: LeadCoordinate?) -> LeadCoordinate? {
        isSpark ? picked : nil
    }

    /// Whether a (late) device GPS fix may be written onto the form. False for Spark once an address was picked.
    static func deviceFixMayApply(isSpark: Bool, picked: LeadCoordinate?) -> Bool {
        pickedOverride(isSpark: isSpark, picked: picked) == nil
    }

    /// The B2B address block shows when the client turned it on (`lead_form.address_on_b2b`) or for Spark & Ray,
    /// whose B2B leads are located by a picked Google address.
    static func b2bAddressShown(addressOnB2b: Bool, isSpark: Bool) -> Bool { addressOnB2b || isSpark }

    /// Text-field strings (6 decimals, as the form stores them) for a coordinate.
    static func formFields(_ c: LeadCoordinate) -> (latitude: String, longitude: String) {
        (String(format: "%.6f", c.latitude), String(format: "%.6f", c.longitude))
    }
}
