import os
import re
import subprocess
import sys
from pathlib import Path

from changelog import git, update_changelog


def main():
    os.chdir(Path(__file__).resolve().parent.parent)
    if (
        len(sys.argv) != 2
        or re.fullmatch(
            r"v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
            r"(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?",
            sys.argv[1],
        )
        is None
    ):
        raise SystemExit("用法：just release v0.1.0")

    tag = sys.argv[1]
    branch = git("branch", "--show-current")
    if not branch:
        raise SystemExit("请在分支上发布。")
    if git("status", "--porcelain"):
        raise SystemExit("请先提交当前修改。")

    subprocess.run(
        [
            "git", "fetch", "--no-tags", "origin",
            "refs/tags/v*:refs/tags/v*", "^refs/tags/v*-dev",
        ],
        check=True,
    )
    existing_tag = subprocess.run(
        ["git", "show-ref", "--verify", "--quiet", f"refs/tags/{tag}"],
        check=False,
    )
    if existing_tag.returncode == 0:
        raise SystemExit(f"{tag} 已存在。")

    pubspec = Path("pubspec.yaml")
    updated = re.sub(
        r"(?m)^version:[^\r\n]*",
        f"version: {tag.removeprefix('v')}",
        pubspec.read_text(encoding="utf-8"),
        count=1,
    )
    update_changelog(tag)
    pubspec.write_text(updated, encoding="utf-8")

    subprocess.run(
        [
            "git",
            "commit",
            "--only",
            "-m",
            f"chore: release {tag}",
            "--",
            "pubspec.yaml",
            "CHANGELOG.md",
        ],
        check=True,
    )
    subprocess.run(["git", "tag", "-a", tag, "-m", f"Release {tag}"], check=True)

    push = [
        "git",
        "push",
        "--atomic",
        "--set-upstream",
        "origin",
        f"HEAD:refs/heads/{branch}",
        f"refs/tags/{tag}",
    ]
    subprocess.run(push, check=True)


if __name__ == "__main__":
    main()
