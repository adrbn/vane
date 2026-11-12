import Foundation

/// Country helpers. Reviews use ISO alpha-3 codes, reports use alpha-2.
public enum Territories {
    // Generated from Natural Earth (public domain) + small App Store territories.
    static let a3to2: [String: String] = ["AFG":"AF","AGO":"AO","AIA":"AI","ALB":"AL","ARE":"AE","ARG":"AR","ARM":"AM","ATA":"AQ","ATF":"TF","ATG":"AG","AUS":"AU","AUT":"AT","AZE":"AZ","BDI":"BI","BEL":"BE","BEN":"BJ","BFA":"BF","BGD":"BD","BGR":"BG","BHR":"BH","BHS":"BS","BIH":"BA","BLR":"BY","BLZ":"BZ","BMU":"BM","BOL":"BO","BRA":"BR","BRB":"BB","BRN":"BN","BTN":"BT","BWA":"BW","CAF":"CF","CAN":"CA","CHE":"CH","CHL":"CL","CHN":"CN","CIV":"CI","CMR":"CM","COD":"CD","COG":"CG","COL":"CO","CPV":"CV","CRI":"CR","CUB":"CU","CYM":"KY","CYP":"CY","CZE":"CZ","DEU":"DE","DJI":"DJ","DMA":"DM","DNK":"DK","DOM":"DO","DZA":"DZ","ECU":"EC","EGY":"EG","ERI":"ER","ESH":"EH","ESP":"ES","EST":"EE","ETH":"ET","FIN":"FI","FJI":"FJ","FLK":"FK","FRA":"FR","FSM":"FM","GAB":"GA","GBR":"GB","GEO":"GE","GHA":"GH","GIN":"GN","GMB":"GM","GNB":"GW","GNQ":"GQ","GRC":"GR","GRD":"GD","GRL":"GL","GTM":"GT","GUY":"GY","HKG":"HK","HND":"HN","HRV":"HR","HTI":"HT","HUN":"HU","IDN":"ID","IND":"IN","IRL":"IE","IRN":"IR","IRQ":"IQ","ISL":"IS","ISR":"IL","ITA":"IT","JAM":"JM","JOR":"JO","JPN":"JP","KAZ":"KZ","KEN":"KE","KGZ":"KG","KHM":"KH","KIR":"KI","KNA":"KN","KOR":"KR","KWT":"KW","LAO":"LA","LBN":"LB","LBR":"LR","LBY":"LY","LCA":"LC","LKA":"LK","LSO":"LS","LTU":"LT","LUX":"LU","LVA":"LV","MAC":"MO","MAR":"MA","MDA":"MD","MDG":"MG","MDV":"MV","MEX":"MX","MKD":"MK","MLI":"ML","MLT":"MT","MMR":"MM","MNE":"ME","MNG":"MN","MOZ":"MZ","MRT":"MR","MSR":"MS","MUS":"MU","MWI":"MW","MYS":"MY","NAM":"NA","NCL":"NC","NER":"NE","NGA":"NG","NIC":"NI","NLD":"NL","NOR":"NO","NPL":"NP","NRU":"NR","NZL":"NZ","OMN":"OM","PAK":"PK","PAN":"PA","PER":"PE","PHL":"PH","PLW":"PW","PNG":"PG","POL":"PL","PRI":"PR","PRK":"KP","PRT":"PT","PRY":"PY","PSE":"PS","QAT":"QA","ROU":"RO","RUS":"RU","RWA":"RW","SAU":"SA","SDN":"SD","SEN":"SN","SGP":"SG","SLB":"SB","SLE":"SL","SLV":"SV","SOM":"SO","SRB":"RS","SSD":"SS","SUR":"SR","SVK":"SK","SVN":"SI","SWE":"SE","SWZ":"SZ","SYC":"SC","SYR":"SY","TCA":"TC","TCD":"TD","TGO":"TG","THA":"TH","TJK":"TJ","TKM":"TM","TLS":"TL","TON":"TO","TTO":"TT","TUN":"TN","TUR":"TR","TWN":"TW","TZA":"TZ","UGA":"UG","UKR":"UA","URY":"UY","USA":"US","UZB":"UZ","VCT":"VC","VEN":"VE","VGB":"VG","VNM":"VN","VUT":"VU","YEM":"YE","ZAF":"ZA","ZMB":"ZM","ZWE":"ZW"]

    public static func alpha2(_ code: String) -> String { code.count == 3 ? (a3to2[code] ?? code) : code }

    public static func name(_ code: String) -> String {
        Locale(identifier: "en").localizedString(forRegionCode: alpha2(code)) ?? code
    }

    public static func flag(_ code: String) -> String {
        let a2 = alpha2(code).uppercased()
        guard a2.count == 2 else { return "🏳️" }
        return String(String.UnicodeScalarView(a2.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }))
    }
}
