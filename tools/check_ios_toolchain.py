"""Fail before signing when the SDK cannot produce an iPhone Duo build."""

import re
import subprocess


def version(command):
    output = subprocess.check_output(command, text=True).strip()
    match = re.search(r"(\d+)\.(\d+)", output)
    if match is None:
        raise SystemExit(f"Cannot read toolchain version: {output}")
    return tuple(map(int, match.groups()))


def main():
    for label, command in (
        ("Xcode", ["xcodebuild", "-version"]),
        ("iPhoneOS SDK", ["xcrun", "--sdk", "iphoneos", "--show-sdk-version"]),
    ):
        actual = version(command)
        if actual < (27, 1):
            raise SystemExit(f"{label} 27.1 or later required for iPhone Duo; got {actual}")
        print(f"{label}: {actual[0]}.{actual[1]}")


if __name__ == "__main__":
    main()
