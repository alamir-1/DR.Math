# Dr. Math Blajat - تطبيق Flutter (WebView)

تطبيق Flutter بسيط يعرض موقعك:
<https://mohamed-abdou-1.github.io/Educational-center-administration-/>

## المشروع جاهز بالكامل ✅

- `lib/main.dart` — الكود الكامل لعرض WebView (مع دعم زر الرجوع، شاشة تحميل، وشاشة خطأ عند فقد الإنترنت)
- `pubspec.yaml` — يحتوي على حزمة `webview_flutter`
- `android/app/src/main/AndroidManifest.xml` — يحتوي على صلاحية الإنترنت
- ملفات Gradle وأيقونات مؤقتة جاهزة أيضاً

## خطوات التشغيل على جهازك

**المتطلبات:** لازم يكون عندك Flutter SDK متثبت.
تثبيت Flutter من هنا: <https://docs.flutter.dev/get-started/install>

1. انسخ ملف `android/local.properties.example` إلى `android/local.properties` وحط فيه مسار تثبيت Flutter عندك.
2. افتح الطرفية (Terminal / CMD) داخل مجلد المشروع ونفّذ:

```
# 1. تحميل الحزم المطلوبة
flutter pub get

# 2. تشغيل التطبيق على جهاز متصل أو محاكي
flutter run

# 3. أو بناء ملف APK جاهز للتثبيت مباشرة
flutter build apk --release
```

بعد الأمر الثالث هتلاقي ملف الـ APK هنا:

```
build/app/outputs/flutter-apk/app-release.apk
```

انسخه لهاتفك وثبّته مباشرة.

## تغيير الأيقونة (لما تبعتلي صورك)

دلوقتي حاطط أيقونة مؤقتة (دائرة بيضاء على خلفية زرقاء) في:
- `android/app/src/main/res/mipmap-mdpi/ic_launcher.png` (48x48)
- `android/app/src/main/res/mipmap-hdpi/ic_launcher.png` (72x72)
- `android/app/src/main/res/mipmap-xhdpi/ic_launcher.png` (96x96)
- `android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png` (144x144)
- `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png` (192x192)

لما تبعتلي صورة الأيقونة، هظبطلك المقاسات دي كلها تلقائيًا وأستبدل الملفات.

بديل أسهل: استخدم حزمة `flutter_launcher_icons` (تبعتلها صورة واحدة 1024x1024 وهي بتعمل كل المقاسات لوحدها):
<https://pub.dev/packages/flutter_launcher_icons>

## ملاحظات

- اسم الحزمة (Package Name) الحالي: `com.mohamedabdou.drmath` — تقدر تغيّره لاحقًا لو هتنشر على Google Play.
- اسم التطبيق الحالي: "Dr. Math Blajat" — لو عايز اسم تاني قولي.
- يدعم الكود زر الرجوع (Back) للتنقل داخل صفحات الموقع بدل ما يقفل التطبيق على طول.
- في حالة فصل النت، بتظهر شاشة خطأ بها زرار "إعادة المحاولة".
