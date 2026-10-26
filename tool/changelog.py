import re
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path


def git(*arguments):
    return subprocess.check_output(
        ["git", *arguments], text=True, encoding="utf-8"
    ).strip()


def release_notes(section):
    changelog = Path("CHANGELOG.md").read_text(encoding="utf-8")
    entry = re.search(
        rf"(?ms)^## {re.escape(section)}(?: - [^\n]*)?\n.*?(?=^## |\Z)",
        changelog,
    )
    return entry[0].strip() + "\n"


def _unreleased_changes():
    tags = git("tag", "--merged", "HEAD", "--list", "v[0-9]*").splitlines()
    previous = (
        git(
            "describe", "--tags", "--abbrev=0", "--match", "v[0-9]*",
            "--exclude", "*-dev",
        )
        if any(not tag.endswith("-dev") for tag in tags)
        else None
    )
    revision = f"{previous}..HEAD" if previous else "HEAD"
    # Exclude commits that only update the changelog itself.
    commits = git("log", "--format=%H%x09%s", revision, "--", ".", ":!CHANGELOG.md")
    lines = []
    for commit in commits.splitlines():
        sha, subject = commit.split("\t", 1)
        lines.append(
            f"- {subject} ([{sha[:7]}](https://github.com/so1ve/bitree/commit/{sha}))"
        )
    return previous, lines


def unreleased_notes():
    _, lines = _unreleased_changes()
    return "\n".join(["## Unreleased", "", *lines]).rstrip() + "\n"


def update_changelog(tag):
    previous, lines = _unreleased_changes()

    changelog = Path("CHANGELOG.md")
    history = re.sub(
        r"\A# Changelog\n+## Unreleased\n.*?(?=^## |\Z)",
        "",
        changelog.read_text(encoding="utf-8"),
        flags=re.MULTILINE | re.DOTALL,
    ).lstrip("\n")

    released_on = datetime.now(timezone(timedelta(hours=8))).date().isoformat()
    lines = [f"## {tag} - {released_on}", "", *lines]
    if previous:
        lines.extend(
            [
                "",
                f"[完整变更](https://github.com/so1ve/bitree/compare/{previous}...{tag})",
            ]
        )

    sections = ["# Changelog", "## Unreleased", "\n".join(lines)]
    if history:
        sections.append(history.rstrip())
    changelog.write_text("\n\n".join(sections) + "\n", encoding="utf-8")
