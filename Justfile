default:
    @just --list

deps:
    flutter pub get

devices:
    flutter devices

run device=os():
    flutter run -d {{ quote(device) }}

fmt:
    dart format lib

fmt-nix:
    nixfmt devenv.nix

analyze:
    flutter analyze

check: analyze

build target=os():
    flutter build {{ quote(target) }}

apk:
    flutter build apk --release --target-platform=android-arm64 --split-per-abi

release version:
    python3 tool/release.py {{ quote(version) }}

doctor:
    flutter doctor -v

clean:
    flutter clean
