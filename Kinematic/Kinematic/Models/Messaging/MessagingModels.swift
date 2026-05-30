//
//  MessagingModels.swift
//  Kinematic
//
//  Wire types for /api/v1/messaging/*. Matches the dashboard's
//  messagingApi.ts and Android's MessagingModels.kt.
//

import Foundation

struct MessagingScopedUser: Codable, Identifiable, Hashable {
    let id: String
    let fullName: String?
    let email: String
    let cityNames: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case email
        case cityNames = "city_names"
    }

    var displayName: String {
        if let n = fullName, !n.isEmpty { return n }
        return email.isEmpty ? "User" : email
    }
}

struct MessagingThreadMember: Codable, Hashable {
    let id: String
    let name: String
}

struct MessagingThread: Codable, Identifiable, Hashable {
    let id: String
    let kind: String                            // "dm" | "team"
    let name: String?
    let displayName: String?
    let lastMessageAt: String?
    let lastMessagePreview: String?
    let unreadCount: Int?
    let memberIds: [String]?
    let members: [MessagingThreadMember]?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case name
        case displayName = "display_name"
        case lastMessageAt = "last_message_at"
        case lastMessagePreview = "last_message_preview"
        case unreadCount = "unread_count"
        case memberIds = "member_ids"
        case members
        case createdAt = "created_at"
    }

    var title: String {
        if let dn = displayName, !dn.isEmpty { return dn }
        if let n = name, !n.isEmpty { return n }
        return kind == "team" ? "Team Chat" : "Direct Message"
    }
}

struct MessagingMessage: Codable, Identifiable, Hashable {
    let id: String
    let threadId: String
    let senderId: String
    let senderName: String?
    let body: String
    let language: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case threadId = "thread_id"
        case senderId = "sender_id"
        case senderName = "sender_name"
        case body
        case language
        case createdAt = "created_at"
    }

    var senderLabel: String {
        if let n = senderName, !n.isEmpty { return n }
        return "User"
    }
}

struct MessagingThreadCreated: Codable {
    let id: String
}
