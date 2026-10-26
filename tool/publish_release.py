import argparse
import hashlib
import json
import os
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory

from changelog import release_notes, unreleased_notes


def gh(*arguments):
    subprocess.run(["gh", *arguments], check=True, stdout=subprocess.DEVNULL)


def github(path):
    result = subprocess.run(
        ["gh", "api", path], capture_output=True, text=True, check=False
    )
    if result.returncode == 0:
        return json.loads(result.stdout)
    if "(HTTP 404)" in result.stderr:
        return None

    raise SystemExit(result.stderr.strip())


def publish_release(repository, tag, sha, notes, assets, existing):
    endpoint = f"repos/{repository}"
    is_dev = tag == "dev"
    if is_dev:
        ref = github(f"{endpoint}/git/ref/tags/dev")
        if ref is not None:
            gh(
                "api",
                "--method",
                "PATCH",
                f"{endpoint}/git/refs/tags/dev",
                "-f",
                f"sha={sha}",
                "-F",
                "force=true",
            )

        # Editing or republishing keeps the old release's position in the list.
        if existing is not None:
            gh("release", "delete", tag, "--repo", repository, "--yes")
        existing = None

    if existing is None:
        command = [
            "release",
            "create",
            tag,
            "--repo",
            repository,
            "--target",
            sha,
            "--draft",
            "--latest=false",
            "--title",
            "Dev Build" if is_dev else f"BITree {tag}",
            "--notes-file",
            str(notes),
        ]
        if is_dev or "-" in tag:
            command.append("--prerelease")

        gh(*command)

    gh(
        "release",
        "upload",
        tag,
        "--repo",
        repository,
        "--clobber",
        *map(str, assets),
    )

    latest = not is_dev and "-" not in tag
    command = [
        "release",
        "edit",
        tag,
        "--repo",
        repository,
        "--draft=false",
        f"--latest={str(latest).lower()}",
        "--notes-file",
        str(notes),
    ]
    if is_dev:
        command.append("--prerelease")
    gh(*command)


def refresh_dev_release(repository):
    endpoint = f"repos/{repository}"
    existing = github(f"{endpoint}/releases/tags/dev")
    if existing is None or existing["draft"]:
        return

    ref = github(f"{endpoint}/git/ref/tags/dev")
    with TemporaryDirectory(prefix="bitree-dev-release-") as directory:
        root = Path(directory)
        assets = root / "assets"
        assets.mkdir()
        # Download everything before replacing the published release.
        gh("release", "download", "dev", "--repo", repository, "--dir", str(assets))
        notes = root / "release-notes.md"
        notes.write_text(existing["body"] or "", encoding="utf-8")
        publish_release(
            repository,
            "dev",
            ref["object"]["sha"],
            notes,
            sorted(assets.iterdir()),
            existing,
        )


def main():
    os.chdir(Path(__file__).resolve().parent.parent)
    parser = argparse.ArgumentParser()
    parser.add_argument("channel", choices=["dev", "release"])
    parser.add_argument("version")
    args = parser.parse_args()

    repository = os.environ["GITHUB_REPOSITORY"]
    sha = os.environ["GITHUB_SHA"]
    tag = "dev" if args.channel == "dev" else args.version
    assets = sorted(Path("dist").glob("BITree-*"))
    if not assets:
        raise SystemExit("没有成功构建的产物可供发布。")

    checksums = Path("dist/SHA256SUMS.txt")
    with checksums.open("w", encoding="utf-8") as output:
        for asset in assets:
            with asset.open("rb") as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            output.write(f"{digest}  {asset.name}\n")

    existing = github(f"repos/{repository}/releases/tags/{tag}")
    if (
        args.channel == "release"
        and existing is not None
        and (not existing["draft"] or existing["target_commitish"] != sha)
    ):
        raise SystemExit(f"{tag} 已发布或存在其他提交的草稿。")

    notes = Path("dist/release-notes.md")
    notes.write_text(
        unreleased_notes() if args.channel == "dev" else release_notes(tag),
        encoding="utf-8",
    )
    publish_release(repository, tag, sha, notes, [*assets, checksums], existing)
    if args.channel == "release":
        refresh_dev_release(repository)


if __name__ == "__main__":
    main()
