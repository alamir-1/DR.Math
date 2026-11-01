import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// الموقع (بث مباشر لما في نت)
const String kSiteUrl =
    'https://mohamed-abdou-1.github.io/Educational-center-administration-/';

/// النسخة الاحتياطية جوه التطبيق (لما مفيش نت)
const String kOfflineAsset = 'assets/index.html';

/// الطريقة الأساسية: حط ملف google-services.json في root الريبو (جنب pubspec.yaml)
/// وسكربت tool/patch_manifest.py هيركّبه لوحده وقت البيلد، والتطبيق بيقرا منه كل حاجة.
/// (اختياري / احتياطي) لو مفيش الملف: حط هنا App ID بتاع تطبيق الأندرويد
/// (Firebase Console ← Project settings ← Your apps ← Android) شكله 1:979908178692:android:xxxxxxxx
const String kAndroidAppId = 'PUT_ANDROID_APP_ID_HERE';

const FirebaseOptions kFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyBb2YaXdhOtn8G7LjUo9hKvLwXDOPCLj1M',
  appId: kAndroidAppId,
  messagingSenderId: '979908178692',
  projectId: 'soon-8c1e6',
  storageBucket: 'soon-8c1e6.firebasestorage.app',
);

const String _kPrefTop = 'bar_top';
const String _kPrefBottom = 'bar_bottom';

Color? _parseHex(dynamic v) {
  if (v is! String) return null;
  final h = v.replaceAll('#', '');
  if (h.length != 6) return null;
  final n = int.tryParse(h, radix: 16);
  return n == null ? null : Color(0xFF000000 | n);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // التطبيق يرسم تحت شريط الحالة وشريط التنقل، واللون بتاعهم بييجي من الصفحة
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // آخر ألوان اتحفظت (من آخر مرة فتحت فيها التطبيق) — عشان الشريط يبدأ
  // بلون السمة الحالية من أول لحظة بدل ما يظهر أبيض وبعدين يتغير.
  Color? top, bottom;
  try {
    final p = await SharedPreferences.getInstance();
    top = _parseHex(p.getString(_kPrefTop));
    bottom = _parseHex(p.getString(_kPrefBottom));
  } catch (_) {}
  runApp(EduApp(savedTop: top, savedBottom: bottom));
}

class EduApp extends StatelessWidget {
  const EduApp({super.key, this.savedTop, this.savedBottom});
  final Color? savedTop;
  final Color? savedBottom;
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Educational Center',
        home: Home(savedTop: savedTop, savedBottom: savedBottom),
      );
}

class Home extends StatefulWidget {
  const Home({super.key, this.savedTop, this.savedBottom});
  final Color? savedTop;
  final Color? savedBottom;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  InAppWebViewController? _c;
  StreamSubscription? _connSub;
  bool _ready = false; // اتحدد نبدأ أونلاين ولا أوفلاين
  bool _startOnline = true;
  bool _offline = false; // الصفحة الحالية جاية من الملف؟
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  bool _dark = false;
  bool _barsSet = false;
  bool _sampled = false; // وصلنا ألوان حقيقية من الصفحة؟
  bool _hadSaved = false; // بدأنا بألوان محفوظة من آخر مرة؟
  Color _topColor = Colors.white; // لون شريط الحالة
  Color _bottomColor = Colors.white; // لون شريط التنقل
  String? _token;
  String? _authKey; // مفتاح المستلم اللي الصفحة بتبعته بعد تسجيل الدخول
  int _retries = 0; // محاولات إعادة التحميل لما يحصل خطأ مؤقت والنت شغال

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // ابدأ بآخر لون محفوظ للشريطين (لو موجود)
    final st = widget.savedTop, sb = widget.savedBottom;
    if (st != null && sb != null) {
      _hadSaved = true;
      _applyBars(st, sb);
    }
    _boot();
  }

  Future<void> _saveBars(Color top, Color bottom) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kPrefTop, _toHex(top));
      await p.setString(_kPrefBottom, _toHex(bottom));
    } catch (_) {}
  }

  String _toHex(Color c) =>
      '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  Future<bool> _hasNet() async {
    final r = await Connectivity().checkConnectivity();
    return !r.contains(ConnectivityResult.none);
  }

  Future<void> _boot() async {
    _startOnline = await _hasNet();
    if (!_startOnline) {
      // أحيانًا أول لحظة بعد فتح التطبيق الاتصال بيبان مقطوع غلط — نستنى ونعيد الفحص
      await Future.delayed(const Duration(milliseconds: 1500));
      _startOnline = await _hasNet();
    }
    // دايمًا نحمّل الموقع الأصلي: الـ Service Worker جوّاه بيفتح النسخة المحفوظة لو مفيش نت
    // (نفس الـ origin فبتفضل الجلسة والبيانات المحفوظة). نسخة الملف بتستخدم بس لو مفيش
    // نسخة محفوظة لسه (أول فتح من غير نت) — ده بيحصل في onReceivedError.
    _offline = false;
    if (mounted) setState(() => _ready = true);

    // رجع النت → حمّل الموقع بدل الملف
    _connSub = Connectivity().onConnectivityChanged.listen((r) {
      final on = !r.contains(ConnectivityResult.none);
      if (on && _offline) _goOnline();
    });

    // بالترتيب (مش مع بعض): طلبين صلاحية إشعارات في نفس اللحظة كانوا بيتعارضوا
    // وساعات الإشعارات كانت بتتمنع من غير ما حد يلاحظ.
    await _initPush();
    await _askPermissionsOnStart();
  }

  /// بيطلب كل الصلاحيات المهمة أول ما التطبيق يفتح (إشعارات، ميكروفون، كاميرا، صور وفيديوهات)
  Future<void> _askPermissionsOnStart() async {
    try {
      // صلاحية الإشعارات بتتطلب في _initPush (مرة واحدة بس)
      final list = <Permission>[
        Permission.microphone,
        Permission.camera,
        Permission.photos, // Android 13+ (READ_MEDIA_IMAGES)
        Permission.videos, // Android 13+ (READ_MEDIA_VIDEO)
        Permission.storage, // Android 12 وأقل
      ];
      for (final p in list) {
        final st = await p.status;
        if (st.isDenied) await p.request(); // واحدة واحدة عشان كل رسالة تظهر لوحدها
      }
      await _askBatteryWhitelistOnce();
    } catch (e) {
      debugPrint('permissions failed: $e');
    }
  }

  /// بعض الموبايلات (شاومي/سامسونج/أوبو...) بتقتل التطبيق في الخلفية وتوقف الإشعارات.
  /// بنطلب مرة واحدة بس استثناء التطبيق من توفير البطارية.
  Future<void> _askBatteryWhitelistOnce() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool('battery_asked') == true) return;
      await p.setBool('battery_asked', true);
      if (!await Permission.ignoreBatteryOptimizations.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (e) {
      debugPrint('battery whitelist failed: $e');
    }
  }

  /// بيطلب صلاحية معينة وقت الحاجة؛ لو اتمنعت للأبد بيفتح إعدادات التطبيق
  Future<bool> _ensure(Permission p) async {
    var st = await p.status;
    if (st.isGranted || st.isLimited) return true;
    st = await p.request();
    if (st.isGranted || st.isLimited) return true;
    if (st.isPermanentlyDenied) await openAppSettings();
    return false;
  }

  void _goOnline() {
    _offline = false;
    _c?.loadUrl(urlRequest: URLRequest(url: WebUri(kSiteUrl)));
  }

  void _goOffline() {
    if (_offline) return;
    _offline = true;
    _c?.loadFile(assetFilePath: kOfflineAsset);
  }

  Future<void> _initPush() async {
    try {
      try {
        // الطريقة الأساسية: الإعدادات من google-services.json (اللي بيتركّب وقت البيلد)
        await Firebase.initializeApp();
      } catch (_) {
        if (!kAndroidAppId.contains(':android:')) {
          debugPrint('push disabled: no google-services.json and no kAndroidAppId');
          return;
        }
        await Firebase.initializeApp(options: kFirebaseOptions);
      }
      final m = FirebaseMessaging.instance;
      await m.setAutoInitEnabled(true);
      m.onTokenRefresh.listen((t) {
        _token = t;
        _sendToken();
      });
      // التوكن الأول (من غير ما نستنى الصلاحية) مع إعادة محاولة لو الخدمة مش جاهزة
      unawaited(_fetchToken());
      // بعدها صلاحية الإشعارات (Android 13+)
      var perm = await m.requestPermission(alert: true, badge: true, sound: true);
      if (perm.authorizationStatus == AuthorizationStatus.denied) {
        // لو اتمنعت للأبد: نفتح إعدادات التطبيق مرة واحدة بس
        final p = await SharedPreferences.getInstance();
        if (p.getBool('notif_settings_asked') != true) {
          await p.setBool('notif_settings_asked', true);
          await openAppSettings();
        }
      }
      await m.setForegroundNotificationPresentationOptions(
          alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('push init failed: $e');
    }
  }

  Future<void> _fetchToken() async {
    for (var i = 0; i < 5 && _token == null; i++) {
      try {
        _token = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        debugPrint('getToken failed (try ${i + 1}): $e');
      }
      if (_token == null) await Future.delayed(Duration(seconds: 2 * (i + 1)));
    }
    debugPrint('FCM token: $_token');
    _sendToken();
  }

  /// بنبعت التوكن للصفحة، والصفحة بتسجله في Firebase تحت المستخدم الحالي
  Future<void> _sendToken() async {
    final t = _token;
    final c = _c;
    if (t == null || c == null) return;
    final j = jsonEncode(t);
    await c.evaluateJavascript(
        source:
            "window.__nativeFcmToken=$j;window.dispatchEvent(new CustomEvent('native-fcm-token',{detail:$j}));");
  }

  Color? _hex(dynamic v) => _parseHex(v);

  /// بيلوّن شريط الحالة وشريط التنقل بنفس لون الصفحة، والأيقونات فاتحة/غامقة حسب اللون
  void _applyBars(Color top, Color bottom, {bool fromPage = false}) {
    if (fromPage) {
      _sampled = true;
      if (top != _topColor || bottom != _bottomColor || !_hadSaved) {
        _hadSaved = true;
        _saveBars(top, bottom); // نحفظه عشان الفتحة الجاية تبدأ بنفس اللون
      }
    }
    if (top == _topColor && bottom == _bottomColor && _barsSet) return;
    _barsSet = true;
    final topDark = ThemeData.estimateBrightnessForColor(top) == Brightness.dark;
    final botDark =
        ThemeData.estimateBrightnessForColor(bottom) == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: top,
      statusBarIconBrightness: topDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: topDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: bottom,
      systemNavigationBarDividerColor: bottom,
      systemNavigationBarIconBrightness:
          botDark ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    ));
    if (mounted) {
      setState(() {
        _topColor = top;
        _bottomColor = bottom;
        _dark = topDark;
      });
    }
  }

  Future<void> _onBack() async {
    final c = _c;
    if (c == null) {
      SystemNavigator.pop();
      return;
    }
    try {
      final closed = await c.evaluateJavascript(
          source:
              "(function(){try{if(typeof openChatRole!=='undefined'&&openChatRole!==null){closeChatPage();return true;}}catch(e){}return false;})()");
      if (closed == true) return;
    } catch (_) {}
    if (await c.canGoBack()) {
      await c.goBack();
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_token == null) {
        _fetchToken();
      } else {
        _sendToken();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connSub?.cancel();
    _progress.dispose();
    super.dispose();
  }

  /// لون المؤشرات: فاتح على الخلفية الغامقة وغامق على الفاتحة
  Color get _fg =>
      ThemeData.estimateBrightnessForColor(_bottomColor) == Brightness.dark
          ? Colors.white70
          : Colors.black54;

  @override
  Widget build(BuildContext context) {
    final bg = _bottomColor;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _onBack();
      },
      child: Scaffold(
        backgroundColor: bg,
        body: Builder(builder: (ctx) {
          final pad = MediaQuery.of(ctx).padding;
          return Column(children: [
            Container(height: pad.top, color: _topColor),
            Expanded(
          child: !_ready
              ? Center(child: CircularProgressIndicator(color: _fg))
              : Stack(children: [
                  InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(kSiteUrl)),
                    initialUserScripts: UnmodifiableListView([
                      // نفس القناة اللي الصفحة بتستخدمها (window.NativeTheme)
                      UserScript(
                        source:
                            "window.NativeTheme={postMessage:function(m){try{window.flutter_inappwebview.callHandler('NativeTheme',m);}catch(e){}}};window.NativeNotifSound={play:function(){try{window.flutter_inappwebview.callHandler('NativeNotifSound');}catch(e){}}};window.NativeAuth={postMessage:function(k){try{window.flutter_inappwebview.callHandler('NativeAuth',k);}catch(e){}}};",
                        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                    ]),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      // الخلفية شفافة لحد ما الصفحة تترسم، فيبان لون السمة بدل الأبيض
                      transparentBackground: true,
                      domStorageEnabled: true,
                      databaseEnabled: true,
                      thirdPartyCookiesEnabled: true,
                      cacheEnabled: true,
                      incognito: false,
                      allowsInlineMediaPlayback: true,
                      supportZoom: false,
                      useHybridComposition: true,
                      cacheMode: CacheMode.LOAD_DEFAULT,
                      allowFileAccess: true,
                      allowContentAccess: true,
                      javaScriptCanOpenWindowsAutomatically: true,
                      mediaPlaybackRequiresUserGesture: false,
                    ),
                    onWebViewCreated: (c) {
                      _c = c;
                      // صوت الإشعار الافتراضي بتاع الموبايل (لما الصفحة تكون مفتوحة)
                      c.addJavaScriptHandler(
                        handlerName: 'NativeNotifSound',
                        callback: (args) {
                          try {
                            FlutterRingtonePlayer().playNotification();
                          } catch (_) {}
                          return null;
                        },
                      );
                      c.addJavaScriptHandler(
                        handlerName: 'NativeAuth',
                        callback: (args) {
                          _authKey = args.isNotEmpty && args.first is String
                              ? args.first as String
                              : null;
                          // بعد تسجيل الدخول نعيد إرسال التوكن عشان الصفحة تسجله للمستخدم ده
                          _sendToken();
                          return null;
                        },
                      );
                      c.addJavaScriptHandler(
                        handlerName: 'NativeTheme',
                        callback: (args) {
                          if (args.isEmpty) return null;
                          final a = args.first;
                          if (a is Map) {
                            // ألوان حقيقية من الصفحة (بتتبع الثيم + لون السمة)
                            final t = _hex(a['top']), b = _hex(a['bottom']);
                            if (t != null && b != null) _applyBars(t, b, fromPage: true);
                          } else if (!_sampled && !_hadSaved) {
                            // احتياطي لحد ما أول لون حقيقي يوصل
                            final dark = a == 'dark';
                            _applyBars(dark ? Colors.black : Colors.white,
                                dark ? Colors.black : Colors.white);
                          }
                          return null;
                        },
                      );
                    },
                    onProgressChanged: (c, p) {
                      _progress.value = p / 100;
                    },
                    onLoadStop: (c, url) async {
                      _retries = 0;
                      await _sendToken();
                    },
                    onReceivedError: (c, request, error) async {
                      if (request.isForMainFrame != true ||
                          error.type == WebResourceErrorType.CANCELLED) {
                        return;
                      }
                      // لو النت شغال فالخطأ غالبًا مؤقت: نعيد المحاولة على الموقع نفسه.
                      // التبديل لنسخة الملف بيغيّر الـ origin فبتضيع الجلسة (تسجيل الدخول)،
                      // فمنعملهوش غير لو مفيش نت فعلًا.
                      if (!_offline && await _hasNet() && _retries < 4) {
                        _retries++;
                        await Future.delayed(Duration(seconds: 2 * _retries));
                        if (mounted && !_offline) {
                          _c?.loadUrl(
                              urlRequest: URLRequest(url: WebUri(kSiteUrl)));
                        }
                        return;
                      }
                      _goOffline();
                    },
                    onPermissionRequest: (c, req) async {
                      var ok = true;
                      if (req.resources
                          .contains(PermissionResourceType.MICROPHONE)) {
                        ok = await _ensure(Permission.microphone) && ok;
                      }
                      if (req.resources.contains(PermissionResourceType.CAMERA)) {
                        ok = await _ensure(Permission.camera) && ok;
                      }
                      return PermissionResponse(
                          resources: req.resources,
                          action: ok
                              ? PermissionResponseAction.GRANT
                              : PermissionResponseAction.DENY);
                    },
                  ),
                  ValueListenableBuilder<double>(
                    valueListenable: _progress,
                    builder: (_, v, __) => v >= 1
                        ? const SizedBox.shrink()
                        : LinearProgressIndicator(
                            value: v,
                            minHeight: 2,
                            color: _fg,
                            backgroundColor: Colors.transparent),
                  ),
                ]),
            ),
            Container(height: pad.bottom, color: _bottomColor),
          ]);
        }),
      ),
    );
  }
}
