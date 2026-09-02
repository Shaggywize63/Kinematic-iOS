import Foundation

/// A generated proposal/quote for a lead. Mirrors crm_proposals; the backend
/// returns a short-lived signed `pdf_url` the client downloads to share/save.
struct Proposal: Codable, Identifiable, Hashable {
    let id: String
    let proposalNumber: String?
    let title: String?
    let status: String?
    let currency: String?
    let grandTotal: Double?
    let coverNote: String?
    let pdfUrl: String?
    let leadId: String?

    enum CodingKeys: String, CodingKey {
        case id, title, status, currency
        case proposalNumber = "proposal_number"
        case grandTotal = "grand_total"
        case coverNote = "cover_note"
        case pdfUrl = "pdf_url"
        case leadId = "lead_id"
    }
}
