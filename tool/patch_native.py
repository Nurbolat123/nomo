#!/usr/bin/env python3
"""Adds store-required settings to the native projects made by `flutter create`.

Run by tool/setup_native.sh. Safe to run more than once.

  python3 tool/patch_native.py passenger
  python3 tool/patch_native.py driver
"""
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

APPS = {
    "passenger": {
        "label": "Nomo",
        "bundle": "com.nomo.passenger",
        "android_permissions": [
            "android.permission.INTERNET",
            "android.permission.ACCESS_FINE_LOCATION",
            "android.permission.ACCESS_COARSE_LOCATION",
        ],
        "plist": {
            "NSLocationWhenInUseUsageDescription":
                "Nomo определяет ваше местоположение, чтобы указать адрес подачи и показать машины рядом. / "
                "Nomo uses your location to set the pickup point and show nearby cars.",
        },
        "background_modes": ["remote-notification"],
    },
    "driver": {
        "label": "Nomo Driver",
        "bundle": "com.nomo.driver",
        "android_permissions": [
            "android.permission.INTERNET",
            "android.permission.ACCESS_FINE_LOCATION",
            "android.permission.ACCESS_COARSE_LOCATION",
            "android.permission.FOREGROUND_SERVICE",
            "android.permission.FOREGROUND_SERVICE_LOCATION",
            "android.permission.POST_NOTIFICATIONS",
            "android.permission.WAKE_LOCK",
            "android.permission.CAMERA",
        ],
        "plist": {
            "NSLocationWhenInUseUsageDescription":
                "Пока вы на линии, Nomo Driver передаёт местоположение, чтобы предлагать ближайшие заказы и показывать пассажиру вашу машину. / "
                "While you are online, Nomo Driver shares your location to offer nearby orders and show passengers your car.",
            "NSLocationAlwaysAndWhenInUseUsageDescription":
                "Пока вы на линии, местоположение передаётся и при свёрнутом приложении, чтобы вы не пропускали заказы. / "
                "While you are online, location is shared with the app in the background so you do not miss orders.",
            "NSCameraUsageDescription":
                "Камера нужна, чтобы сфотографировать документы и машину для регистрации. / "
                "The camera is used to photograph your documents and car for sign-up.",
            "NSPhotoLibraryUsageDescription":
                "Доступ к фото нужен, чтобы загрузить снимки документов. / "
                "Photo access is used to upload pictures of your documents.",
        },
        "background_modes": ["location", "remote-notification"],
    },
}

KTS_KEYSTORE = """val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
"""

KTS_IMPORTS = "import java.io.FileInputStream\nimport java.util.Properties\n\n"

KTS_SIGNING = """    signingConfigs {
        create("release") {
            if (!keystoreProperties.isEmpty) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

"""

QUERIES = """    <queries>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
        <intent>
            <action android:name="android.intent.action.DIAL" />
            <data android:scheme="tel" />
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="tel" />
        </intent>
        <package android:name="ru.dublgis.dgismobile" />
        <package android:name="ru.yandex.yandexnavi" />
        <package android:name="com.google.android.apps.maps" />
    </queries>
"""


def patch_android(app: str, cfg: dict) -> None:
    base = ROOT / "apps" / app / "android"
    manifest = base / "app" / "src" / "main" / "AndroidManifest.xml"
    text = manifest.read_text()
    for perm in cfg["android_permissions"]:
        line = f'    <uses-permission android:name="{perm}" />\n'
        if perm not in text:
            text = text.replace("    <application", line + "    <application", 1)
    text = re.sub(r'android:label="[^"]*"', f'android:label="{cfg["label"]}"', text, count=1)
    if "dgismobile" not in text:
        if "<queries>" in text:
            # Flutter's template already has a <queries> block: add our entries inside it.
            inner = "\n".join(QUERIES.splitlines()[1:-1]) + "\n"
            text = re.sub(r"(<queries>\s*\n)", lambda m: m.group(1) + inner, text, count=1)
        else:
            text = text.replace("</manifest>", QUERIES + "</manifest>")
    manifest.write_text(text)
    print("patched", manifest)

    for gradle in [base / "app" / "build.gradle.kts", base / "app" / "build.gradle"]:
        if not gradle.exists():
            continue
        g = gradle.read_text()
        g = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 28", g)
        g = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 28", g)
        if gradle.suffix == ".kts" and "keystoreProperties" not in g:
            # Release signing from android/key.properties (see docs/release.md).
            g = KTS_IMPORTS + g
            g = g.replace("android {", KTS_KEYSTORE + "\nandroid {", 1)
            g = g.replace("    buildTypes {", KTS_SIGNING + "    buildTypes {", 1)
            g = g.replace('signingConfig = signingConfigs.getByName("debug")',
                          'signingConfig = if (keystoreProperties.isEmpty) signingConfigs.getByName("debug") else signingConfigs.getByName("release")')
        gradle.write_text(g)
        print("patched", gradle)


def patch_ios(app: str, cfg: dict) -> None:
    ios = ROOT / "apps" / app / "ios"
    plist_path = ios / "Runner" / "Info.plist"
    with plist_path.open("rb") as f:
        plist = plistlib.load(f)
    plist.update(cfg["plist"])
    plist["CFBundleDisplayName"] = cfg["label"]
    plist["ITSAppUsesNonExemptEncryption"] = False
    plist["LSApplicationQueriesSchemes"] = ["tel", "dgis", "yandexnavi", "comgooglemaps", "maps"]
    modes = set(plist.get("UIBackgroundModes", []))
    modes.update(cfg["background_modes"])
    plist["UIBackgroundModes"] = sorted(modes)
    with plist_path.open("wb") as f:
        plistlib.dump(plist, f)
    print("patched", plist_path)

    privacy_src = ROOT / "apps" / app / "ios_extra" / "PrivacyInfo.xcprivacy"
    privacy_dst = ios / "Runner" / "PrivacyInfo.xcprivacy"
    shutil.copy(privacy_src, privacy_dst)
    print("copied", privacy_dst)
    shutil.copy(ROOT / "apps" / app / "ios_extra" / "ExportOptions.plist", ios / "ExportOptions.plist")
    # Add the privacy manifest to the Runner target (needs the xcodeproj gem from CocoaPods).
    ruby = f"""
require 'xcodeproj'
p = Xcodeproj::Project.open('{ios / "Runner.xcodeproj"}')
t = p.targets.find {{ |x| x.name == 'Runner' }}
g = p.main_group['Runner']
unless g.files.any? {{ |f| f.path == 'PrivacyInfo.xcprivacy' }}
  ref = g.new_file('PrivacyInfo.xcprivacy')
  t.resources_build_phase.add_file_reference(ref)
  p.save
end
p.targets.each {{ |x| x.build_configurations.each {{ |c| c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0' }} }}
p.build_configurations.each {{ |c| c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0' }}
p.save
"""
    try:
        subprocess.run(["ruby", "-e", ruby], check=True)
        print("added PrivacyInfo.xcprivacy to Runner target, iOS 16.0")
    except Exception as e:  # noqa: BLE001
        print("! Could not edit the Xcode project automatically:", e)
        print("  Open ios/Runner.xcworkspace in Xcode, drag PrivacyInfo.xcprivacy into Runner (Target: Runner),")
        print("  and set iOS Deployment Target to 16.0.")

    podfile = ios / "Podfile"
    if podfile.exists():
        pf = podfile.read_text()
        pf = re.sub(r"^#?\s*platform :ios, '[\d.]+'", "platform :ios, '16.0'", pf, flags=re.M)
        podfile.write_text(pf)
        print("patched", podfile)


if __name__ == "__main__":
    targets = sys.argv[1:] or list(APPS)
    for name in targets:
        cfg = APPS[name]
        if (ROOT / "apps" / name / "android").exists():
            patch_android(name, cfg)
        if (ROOT / "apps" / name / "ios").exists():
            patch_ios(name, cfg)
