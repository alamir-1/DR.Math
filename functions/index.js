const { onValueCreated } = require("firebase-functions/v2/database");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
admin.initializeApp();

/* كل إشعار جديد بيتكتب في notifications/<recipient>/<id> (التطبيق بيعمل كده)
   بنبعته كـ Push لكل أجهزة المستخدم المسجّلة في fcmTokens/<recipient> —
   وبيوصل والتطبيق مقفول. */
exports.sendPush = onValueCreated(
  { ref: "/notifications/{recipient}/{id}", region: "us-central1", instance: "soon-8c1e6-default-rtdb" },
  async (event) => {
    const n = (event.data && event.data.val()) || {};
    const recipient = event.params.recipient;
    if (n.read) return;

    const snap = await admin.database().ref("fcmTokens/" + recipient).get();
    if (!snap.exists()) {
      logger.info("no fcm tokens for recipient", { recipient });
      return;
    }
    const tokens = Object.keys(snap.val());
    if (!tokens.length) return;

    const title = String(n.title || "إشعار جديد");
    const body = String(n.body || "");

    const res = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      // نسخة من البيانات كـ data عشان لو احتجناها في التطبيق
      data: { category: String(n.category || ""), title, body },
      android: {
        priority: "high",
        ttl: 86400000, // 24 ساعة (بالمللي ثانية)
        notification: {
          channelId: "edu_high", // نفس القناة اللي MainActivity بتعملها (صوت الموبايل الافتراضي)
          sound: "default",
          defaultSound: true,
          defaultVibrateTimings: true,
          priority: "high",
          visibility: "public",
          icon: "ic_stat_notify",
          color: "#3FA535",
        },
      },
    });

    // نمسح بس التوكنات الميتة فعلًا. (قبل كده كنا بنمسح عند invalid-argument، وده خطأ:
    // أي مشكلة في شكل الرسالة كانت بتمسح كل التوكنات السليمة وبعدها الإشعارات تقف نهائيًا.)
    const dead = [];
    res.responses.forEach((r, i) => {
      if (r.success) return;
      const code = r.error && r.error.code;
      logger.warn("push failed", { recipient, code, message: r.error && r.error.message });
      if (code === "messaging/registration-token-not-registered") dead.push(tokens[i]);
    });
    logger.info("push sent", { recipient, ok: res.successCount, failed: res.failureCount });
    await Promise.all(dead.map((t) => admin.database().ref("fcmTokens/" + recipient + "/" + t).remove()));
  }
);
