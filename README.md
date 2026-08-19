# Virtualization Smoke Test APK

APK tối thiểu dùng để kiểm tra chuỗi Android Emulator trên máy Windows:

1. AVD boot thành công.
2. `adb` nhìn thấy emulator.
3. Cài được APK build từ GitHub Actions.
4. Launch được activity.
5. App hiển thị Android API, version, model và ABI của máy ảo.

## Build

GitHub Actions workflow: `.github/workflows/build-apk.yml`

Artifact sau khi build: `vm-smoke-test-apk` -> `app-debug.apk`.

## Test trên máy Windows

Sau khi tải `app-debug.apk` về thư mục hiện tại:

```bat
adb devices
adb install -r app-debug.apk
adb shell am start -n com.banupham.virtualizationtest/.MainActivity
adb shell getprop ro.kernel.qemu
adb shell getprop ro.product.cpu.abi
adb shell getprop ro.build.version.sdk
```

Kỳ vọng:

- `adb devices` có một dòng emulator ở trạng thái `device`.
- `adb install` trả về `Success`.
- Activity mở và hiện `VM SMOKE TEST: PASS`.
- `ro.kernel.qemu` thường trả `1` trên Android Emulator.
- API của AVD `poc_api30_atd` phải trả `30` nếu đúng AVD đang được test.
