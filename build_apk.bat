@echo off
title Build CCTV APK
echo =======================================================
echo  Building Smart CCTV Android APK...
echo =======================================================
cd cctv_app
flutter build apk --release
echo.
echo =======================================================
echo  APK Build Finished!
echo  Location: cctv_app\build\app\outputs\flutter-apk\app-release.apk
echo =======================================================
pause
