// Water reminder: every 30 minutes, hour or 2 hours (Settings → Remind me to drink water, off by
// default), the office shows a small card asking you to drink some water. "Done" starts the next
// interval, "Later" asks again in 10 minutes; unanswered, it asks again after the next interval.
// While the window is not on screen a notification says it too.

import Cocoa
import UserNotifications

let WATER_CHOICES = [0, 30, 60, 120]             // the Settings menu, in minutes; 0 = off
let WATER_LATER: TimeInterval = 10 * 60
var waterDue: Date? = nil                         // the next reminder, while one is set

extension AppDelegate {
    var waterMinutes: Int {
        get { defaults.integer(forKey: "waterMinutes") }    // 0 (off) until picked in Settings
        set { defaults.set(newValue, forKey: "waterMinutes"); scheduleWater(after: TimeInterval(newValue * 60)) }
    }

    /// The next reminder `after` seconds from now, or none while it is off.
    func scheduleWater(after s: TimeInterval) { waterDue = waterMinutes > 0 ? Date().addingTimeInterval(s) : nil }

    /// Polled with everything else (every 2 s): show the card when one is due.
    func checkWater() {
        guard let due = waterDue, Date() >= due else { return }
        let mins = waterMinutes
        scheduleWater(after: TimeInterval(mins * 60))       // unanswered: again after the next interval
        web.evaluateJavaScript("window.showWater && showWater(\(mins))", completionHandler: nil)
        if sound { NSSound(named: "Purr")?.play() }
        if !window.isVisible || window.isMiniaturized || !window.occlusionState.contains(.visible) { notifyWater() }
    }

    /// The card's buttons: "done" or "later".
    func waterAnswered(_ a: String) { scheduleWater(after: a == "later" ? WATER_LATER : TimeInterval(waterMinutes * 60)) }

    func notifyWater() {
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let n = UNMutableNotificationContent()
            n.title = "💧 Time for some water"
            n.body = "A glass of water, then back to it."
            c.add(UNNotificationRequest(identifier: "water", content: n, trigger: nil))
        }
    }

    @objc func pickWater(_ sender: NSPopUpButton) {
        waterMinutes = WATER_CHOICES[min(max(0, sender.indexOfSelectedItem), WATER_CHOICES.count - 1)]
    }
}
