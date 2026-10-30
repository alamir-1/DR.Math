const { onValueCreated } = require("firebase-functions/v2/database");
const admin = require("firebase-admin");
admin.initializeApp();

/* كل إشعار جديد بيتكتب في notifications/<recipient>/<id> (التطبيق بيعمل كده)
   بنبعته كـ Push لكل أجهزة المستخدم المسجّلة في fcmTokens/<recipient> —
   وبيوصل والتطبيق مقفول. */
exports.sendPush = onValueCreated(
  { ref: "/notifications/{recipient}/{id}", region: "us-central1", instance: "soon-8c1e6-default-rtdb" },
  async (event) => {
    const n = event.data.val() || {};
    if (n.read) return;
    const recipient = event.params.recipient;
    const snap = await admin.database().ref("fcmTokens/" + recipient).get();
    if (!snap.exists()) return;
    const tokens = Object.keys(snap.val());
    const res = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title: n.title || "إشعار جديد", body: n.body || "" },
      data: { category: String(n.category || "") },
      android: {
        priority: "high",
        ttl: 86400000,
        notification: {
          channelId: "edu_high",      // نفس القناة اللي MainActivity بتعملها (صوت الموبايل الافتراضي)
          sound: "default",
          defaultSound: true,
          defaultVibrateTimings: true,
          notificationPriority: "PRIORITY_HIGH",
          visibility: "PUBLIC",
          icon: "ic_stat_notify",
          color: "#3FA535",
        },
      },
    });
    const dead = [];
    res.responses.forEach((r, i) => {
      const c = r.error && r.error.code;
      if (!r.success && (c === "messaging/registration-token-not-registered" || c === "messaging/invalid-registration-token" || c === "messaging/invalid-argument")) dead.push(tokens[i]);
    });
    await Promise.all(dead.map((t) => admin.database().ref("fcmTokens/" + recipient + "/" + t).remove()));
  }
);
