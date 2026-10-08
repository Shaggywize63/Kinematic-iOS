//
//  NotificationRouteTests.swift
//  KinematicTests
//
//  Which screen a tapped notification opens. Every case is a real notification the backend
//  writes (see Kinematic/docs/NOTIFICATIONS.md): the payload is the flat string map APNs
//  delivers, with the `kind` the server always adds. Mirrors the Android NotificationRouteTest.
//

import XCTest
@testable import Kinematic

final class NotificationRouteTests: XCTestCase {

    private func route(_ d: [String: String]) -> NotificationTarget? { NotificationRoute.resolve(d) }

    // MARK: leads / deals

    func testEveryLeadNotificationOpensTheLead() {
        for kind in ["lead_assigned", "new_lead", "lead_pending_approval", "lead_approval_decided",
                     "lead_from_google_ads", "conversation_ready", "crm_lead_stagnant", "crm_lead_escalation"] {
            XCTAssertEqual(route(["kind": kind, "lead_id": "L1"]), .lead("L1"), kind)
        }
    }

    func testEveryDealNotificationOpensTheDeal() {
        for kind in ["deal_assigned", "deal_won", "deal_lost", "deal_stage_changed",
                     "crm_deal_closing_soon", "crm_deal_overdue"] {
            XCTAssertEqual(route(["kind": kind, "deal_id": "D1"]), .deal("D1"), kind)
        }
    }

    func testALeadKindWithoutItsIdHasNoScreen() {
        XCTAssertNil(route(["kind": "lead_assigned"]))
        XCTAssertNil(route(["kind": "deal_won", "lead_id": "L1"]))
    }

    func testAnActivityOpensItsLeadElseItsDealElseTheActivitiesList() {
        XCTAssertEqual(route(["kind": "activity_assigned", "activity_id": "A1", "lead_id": "L1", "deal_id": "D1"]), .lead("L1"))
        XCTAssertEqual(route(["kind": "activity_assigned", "activity_id": "A1", "deal_id": "D1"]), .deal("D1"))
        XCTAssertEqual(route(["kind": "crm_task_overdue", "activity_id": "A1"]), .activities)
        XCTAssertEqual(route(["kind": "activity_assigned", "lead_id": "null"]), .activities)
    }

    func testAnAutomationOpensTheRecordItNames() {
        XCTAssertEqual(route(["kind": "automation", "entity": "lead", "entity_id": "L2"]), .lead("L2"))
        XCTAssertEqual(route(["kind": "automation", "entity": "deal", "entity_id": "D2"]), .deal("D2"))
        // the dynamic <entity>_id key alone is enough
        XCTAssertEqual(route(["kind": "automation", "entity": "lead", "lead_id": "L3"]), .lead("L3"))
        // contacts and accounts have no id-based screen on iOS
        XCTAssertNil(route(["kind": "automation", "entity": "contact", "entity_id": "C2"]))
        XCTAssertNil(route(["kind": "automation", "entity": "account", "entity_id": "AC2"]))
    }

    // MARK: expenses, leave, attendance

    func testExpenseNotificationsOpenTheClaim() {
        for kind in ["expense_submitted", "expense_decision", "expense_escalated", "expense_reimbursed", "expense_cancelled"] {
            XCTAssertEqual(route(["kind": kind, "claim_id": "C1"]), .expenseClaim("C1"), kind)
        }
        XCTAssertNil(route(["kind": "expense_submitted"]))
    }

    func testALeaveRequestAndItsCancellationGoToTheApproverADecisionToTheApplicant() {
        XCTAssertEqual(route(["kind": "leave_request", "request_id": "R1"]), .leaveApprovals)
        XCTAssertEqual(route(["kind": "leave_cancelled", "request_id": "R1"]), .leaveApprovals)
        XCTAssertEqual(route(["kind": "leave_decision", "request_id": "R1", "decision": "approved"]), .leave)
    }

    func testRegularizationRequestsGoToApprovalsDecisionsToTheRep() {
        XCTAssertEqual(route(["kind": "att_reg_request", "request_id": "R1"]), .leaveApprovals)
        XCTAssertEqual(route(["kind": "att_reg_decision", "request_id": "R1"]), .regularization)
    }

    // MARK: field force, chat, broadcast, stock

    func testFieldForceAlerts() {
        XCTAssertEqual(route(["kind": "missed_visits", "plan_id": "P1"]), .routePlans)
        XCTAssertEqual(route(["kind": "sos", "sos_id": "S1"]), .sos)
        XCTAssertEqual(route(["kind": "kini_no_checkin"]), .checkIn)
        XCTAssertEqual(route(["kind": "checkout_reminder", "attendance_id": "A1"]), .checkIn)
        XCTAssertEqual(route(["kind": "kini_cold_deals", "count": "3"]), .deals)
    }

    func testAChatMessageOpensItsThreadElseTheInbox() {
        XCTAssertEqual(route(["kind": "message", "thread_id": "T1", "message_id": "M1"]), .chatThread("T1"))
        XCTAssertEqual(route(["kind": "message"]), .chatInbox)
    }

    func testAMentionOpensTheChatThreadOrTheLeadItHappenedIn() {
        XCTAssertEqual(route(["kind": "mention", "source_kind": "message", "source_id": "M1", "thread_id": "T1"]), .chatThread("T1"))
        XCTAssertEqual(route(["kind": "mention", "source_kind": "lead_update", "source_id": "U1", "lead_id": "L1"]), .lead("L1"))
        XCTAssertNil(route(["kind": "mention", "source_kind": "message", "source_id": "M1"]))
    }

    func testBroadcastBriefingAndStock() {
        XCTAssertEqual(route(["kind": "broadcast", "broadcast_id": "B1"]), .broadcast)
        XCTAssertEqual(route(["kind": "crm_home"]), .crmHome)
        XCTAssertEqual(route(["kind": "low_stock"]), .stock)
        XCTAssertEqual(route(["kind": "stock_expiry", "batch_id": "B1"]), .stock)
    }

    func testKindsWithNoMobileScreenResolveToNothing() {
        for kind in ["route_deviation", "security_alert", "location_off", "kini_reminder", "finance_invoice_due"] {
            XCTAssertNil(route(["kind": kind, "outlet_id": "O1"]), kind)
        }
    }

    // MARK: older servers / rows

    func testAPayloadWithNoKindStillResolvesFromTypeOrNudgeKind() {
        XCTAssertEqual(route(["type": "leave_request"]), .leaveApprovals)
        XCTAssertEqual(route(["type": "broadcast"]), .broadcast)
        XCTAssertEqual(route(["nudge_kind": "cold_deals"]), .deals)
        XCTAssertEqual(route(["nudge_kind": "no_checkin"]), .checkIn)
    }

    func testKindWinsOverType() {
        XCTAssertEqual(route(["kind": "crm_home", "type": "daily_briefing"]), .crmHome)
    }

    func testIdsStillRouteWhenTheKindIsMissingUnknownOrGeneral() {
        XCTAssertEqual(route(["lead_id": "L1"]), .lead("L1"))
        XCTAssertEqual(route(["deal_id": "D1"]), .deal("D1"))
        XCTAssertEqual(route(["kind": "general", "lead_id": "L1"]), .lead("L1"))
        XCTAssertEqual(route(["kind": "some_future_kind", "deal_id": "D1"]), .deal("D1"))
        XCTAssertNil(route(["kind": "some_future_kind"]))
    }

    func testTheKindDecidesWhichIdIsUsedAndWithoutOneALeadBeatsADeal() {
        XCTAssertEqual(route(["kind": "crm_deal_overdue", "deal_id": "D1", "lead_id": "L1"]), .deal("D1"))
        XCTAssertEqual(route(["lead_id": "L1", "deal_id": "D1"]), .lead("L1"))
    }

    // MARK: tapping a push

    func testAPushWithNoScreenOfItsOwnOpensTheNotificationList() {
        let p = ["notification_id": "N1", "kind": "security_alert", "alert_id": "A1"]
        XCTAssertNil(NotificationRoute.resolve(p))
        XCTAssertEqual(NotificationRoute.forPush(p), .notificationList)
    }

    func testAPushWithAScreenOpensItNotTheList() {
        XCTAssertEqual(NotificationRoute.forPush(["notification_id": "N1", "kind": "lead_assigned", "lead_id": "L1"]), .lead("L1"))
    }

    func testSomethingThatIsNotANotificationNeverOpensTheList() {
        XCTAssertNil(NotificationRoute.forPush(["foo": "bar"]))
    }

    // MARK: payload helpers

    func testUserInfoBecomesAFlatPayloadWithoutTheApsEnvelope() {
        let info: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "t", "body": "b"], "sound": "default"],
            "notification_id": "N1", "kind": "lead_assigned", "lead_id": "L1", "count": 3, "ok": NSNull(),
        ]
        let payload = NotificationRoute.payload(fromUserInfo: info)
        XCTAssertNil(payload["aps"])
        XCTAssertNil(payload["ok"])
        XCTAssertEqual(payload["lead_id"], "L1")
        XCTAssertEqual(payload["count"], "3")
        XCTAssertEqual(NotificationRoute.forPush(payload), .lead("L1"))
    }

    func testARowsDataObjectBecomesAFlatPayload() {
        let payload = NotificationRoute.payload(fromJSON: ["kind": "sos", "sos_id": "S1", "lat": 12.5, "gone": NSNull()])
        XCTAssertEqual(payload["kind"], "sos")
        XCTAssertEqual(payload["lat"], "12.5")
        XCTAssertNil(payload["gone"])
        XCTAssertEqual(NotificationRoute.resolve(payload), .sos)
    }
}
