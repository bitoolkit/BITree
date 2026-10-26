import os
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def main():
    os.chdir(Path(__file__).resolve().parent.parent)

    ref = os.environ["GITHUB_REF"]
    sha = os.environ["GITHUB_SHA"]
    pubspec_version = re.search(
        r"^version:\s*(\S+)", Path("pubspec.yaml").read_text(), re.MULTILINE
    )[1]
    native_version = pubspec_version.split("+")[0].split("-")[0]
    is_release = ref.startswith("refs/tags/v")
    if is_release:
        version = ref.removeprefix("refs/tags/")
    else:
        if "-" not in pubspec_version:
            major, minor, _ = map(int, native_version.split("."))
            native_version = f"{major}.{minor + 1}.0"
        version = f"v{native_version}-dev.{sha[:7]}"

    commit_time = int(
        subprocess.check_output(
            ["git", "show", "-s", "--format=%ct", "HEAD"], text=True
        )
    )
    epoch = int(datetime(2020, 1, 1, tzinfo=timezone.utc).timestamp())
    # The two workflows share one sequence; a release sorts after its dev build.
    build_number = (commit_time - epoch) * 2 + int(is_release)

    outputs = {
        "version": version,
        "native_version": native_version,
        "build_number": str(build_number),
    }
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        output.writelines(f"{key}={value}\n" for key, value in outputs.items())


if __name__ == "__main__":
    main()
