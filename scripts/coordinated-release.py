#!/usr/bin/env python3
"""Interactively commit, push, and tag Git repositories in one directory."""

from __future__ import annotations

import argparse
import getpass
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
from urllib.parse import urlparse


def run_git(
    repository: Path,
    *arguments: str,
    check: bool = True,
    capture: bool = False,
    authentication: tuple[Path, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    """Run Git without invoking a shell or exposing credentials in arguments."""
    environment = os.environ.copy()
    command = ["git", "-C", str(repository)]
    if authentication is not None:
        askpass, token = authentication
        command.extend(
            [
                "-c",
                "credential.helper=",
                "-c",
                "credential.username=x-access-token",
            ]
        )
        environment.update(
            {
                "GIT_ASKPASS": str(askpass),
                "GIT_TERMINAL_PROMPT": "0",
                "MURCHALKA_GIT_TOKEN": token,
            }
        )
    command.extend(arguments)
    return subprocess.run(
        command,
        check=check,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        env=environment,
    )


def captured_git(repository: Path, *arguments: str) -> str:
    """Return trimmed Git output."""
    return run_git(repository, *arguments, capture=True).stdout.strip()


def ask_yes_no(prompt: str) -> bool:
    """Read an explicit yes or no answer."""
    while True:
        answer = input(f"{prompt} [y/n]: ").strip().lower()
        if answer in {"y", "yes"}:
            return True
        if answer in {"n", "no"}:
            return False
        print("Введите y или n.")


def required_input(prompt: str) -> str:
    """Read a required non-empty value."""
    while True:
        value = input(prompt).strip()
        if value:
            return value
        print("Значение не может быть пустым.")


def discover_repositories(root: Path) -> list[Path]:
    """Find immediate child directories containing Git metadata."""
    return sorted(
        (path for path in root.iterdir() if path.is_dir() and (path / ".git").exists()),
        key=lambda path: path.name.casefold(),
    )


def show_changes(repository: Path, status_output: str) -> None:
    """Show every path that `git add -A` will stage and a tracked diff summary."""
    print(f"\n{'=' * 78}\n{repository.name}\n{'=' * 78}")
    if not status_output:
        print("Рабочее дерево чистое: коммит создавать не из чего.")
        return
    print("Будет добавлено командой git add -A:")
    print(status_output)
    summary = run_git(
        repository,
        "diff",
        "--stat",
        "HEAD",
        check=False,
        capture=True,
    ).stdout.strip()
    if summary:
        print("\nСводка изменений:")
        print(summary)


def normalize_github_url(remote_url: str) -> str:
    """Convert common GitHub SSH URLs to HTTPS without changing repository config."""
    if remote_url.startswith("git@github.com:"):
        return "https://github.com/" + remote_url.removeprefix("git@github.com:")
    if remote_url.startswith("ssh://git@github.com/"):
        return "https://github.com/" + remote_url.removeprefix("ssh://git@github.com/")
    parsed = urlparse(remote_url)
    if (
        parsed.scheme != "https"
        or parsed.hostname != "github.com"
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError(
            "remote должен быть безопасным GitHub HTTPS или SSH URL, "
            f"получено: {remote_url}"
        )
    return remote_url


def create_askpass(directory: Path) -> Path:
    """Create a credential helper that reads the token only from process environment."""
    path = directory / "git-askpass.sh"
    path.write_text(
        "#!/bin/sh\n"
        "case \"$1\" in\n"
        "  *Username*) printf '%s\\n' 'x-access-token' ;;\n"
        "  *) printf '%s\\n' \"$MURCHALKA_GIT_TOKEN\" ;;\n"
        "esac\n",
        encoding="utf-8",
    )
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


def validate_tag(repository: Path, tag: str) -> None:
    """Validate a tag name with Git's own reference rules."""
    result = run_git(repository, "check-ref-format", f"refs/tags/{tag}", check=False, capture=True)
    if result.returncode != 0:
        raise ValueError(f"Некорректное имя тега: {tag}")


def remote_tag_commit(
    repository: Path,
    remote_url: str,
    tag: str,
    authentication: tuple[Path, str],
) -> str | None:
    """Return the remote tag's peeled commit when it exists."""
    result = run_git(
        repository,
        "ls-remote",
        "--tags",
        remote_url,
        f"refs/tags/{tag}",
        f"refs/tags/{tag}^{{}}",
        check=False,
        capture=True,
        authentication=authentication,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Не удалось проверить удалённый тег.")
    references = {}
    for line in result.stdout.splitlines():
        object_id, reference = line.split(maxsplit=1)
        references[reference] = object_id
    return references.get(f"refs/tags/{tag}^{{}}") or references.get(f"refs/tags/{tag}")


def ensure_local_tag(repository: Path, tag: str, commit_message: str) -> str:
    """Create an annotated tag, or accept an identical existing local tag."""
    head = captured_git(repository, "rev-parse", "HEAD")
    existing = run_git(repository, "rev-parse", f"refs/tags/{tag}^{{commit}}", check=False, capture=True)
    if existing.returncode == 0:
        if existing.stdout.strip() != head:
            raise RuntimeError(f"Локальный тег {tag} уже указывает на другой коммит.")
        print(f"Локальный тег {tag} уже указывает на HEAD; повторно не создаю.")
        return head
    run_git(repository, "tag", "--annotate", tag, "--message", f"Release {tag}: {commit_message}")
    return head


def current_branch(repository: Path) -> str:
    """Return the checked-out branch and reject detached HEAD."""
    result = run_git(
        repository,
        "symbolic-ref",
        "--quiet",
        "--short",
        "HEAD",
        check=False,
        capture=True,
    )
    branch = result.stdout.strip()
    if result.returncode != 0 or not branch:
        raise RuntimeError("Нельзя публиковать из detached HEAD.")
    return branch


def preflight_repository(
    repository: Path,
    has_changes: bool,
    tag: str,
    remote_name: str,
    authentication: tuple[Path, str],
) -> tuple[str, str]:
    """Validate credentials and release invariants without changing the repository."""
    branch = current_branch(repository)
    validate_tag(repository, tag)
    remote_url = normalize_github_url(
        captured_git(repository, "remote", "get-url", "--push", remote_name)
    )

    print(f"{repository.name}: проверка права push в {branch}")
    dry_run = run_git(
        repository,
        "push",
        "--dry-run",
        remote_url,
        f"HEAD:refs/heads/{branch}",
        check=False,
        capture=True,
        authentication=authentication,
    )
    if dry_run.returncode != 0:
        raise RuntimeError(dry_run.stderr.strip() or "Проверка права push завершилась ошибкой.")

    head = captured_git(repository, "rev-parse", "HEAD")
    local_tag = run_git(
        repository,
        "rev-parse",
        f"refs/tags/{tag}^{{commit}}",
        check=False,
        capture=True,
    )
    if local_tag.returncode == 0 and (has_changes or local_tag.stdout.strip() != head):
        raise RuntimeError(f"Локальный тег {tag} нельзя использовать для нового коммита.")

    published_commit = remote_tag_commit(repository, remote_url, tag, authentication)
    if published_commit is not None and (has_changes or published_commit != head):
        raise RuntimeError(f"Удалённый тег {tag} нельзя использовать для нового коммита.")
    return branch, remote_url


def publish_repository(
    repository: Path,
    has_changes: bool,
    commit_message: str,
    tag: str,
    branch: str,
    remote_url: str,
    authentication: tuple[Path, str],
) -> None:
    """Stage, commit, push, tag, and push the tag for one repository."""
    if has_changes:
        run_git(repository, "add", "--all")
        staged = captured_git(repository, "diff", "--cached", "--name-status")
        if not staged:
            raise RuntimeError("После git add -A нет staged-изменений для коммита.")
        print(f"\n{repository.name}: staged-изменения")
        print(staged)
        run_git(repository, "commit", "--message", commit_message)

    print(f"{repository.name}: push ветки {branch}")
    run_git(
        repository,
        "push",
        remote_url,
        f"HEAD:refs/heads/{branch}",
        authentication=authentication,
    )

    head = captured_git(repository, "rev-parse", "HEAD")
    published_commit = remote_tag_commit(repository, remote_url, tag, authentication)
    if published_commit is not None:
        if published_commit != head:
            raise RuntimeError(f"Удалённый тег {tag} уже указывает на другой коммит.")
        ensure_local_tag(repository, tag, commit_message)
        print(f"{repository.name}: удалённый тег {tag} уже опубликован на HEAD.")
        return

    ensure_local_tag(repository, tag, commit_message)
    print(f"{repository.name}: push тега {tag}")
    run_git(
        repository,
        "push",
        remote_url,
        f"refs/tags/{tag}:refs/tags/{tag}",
        authentication=authentication,
    )


def parse_arguments() -> argparse.Namespace:
    """Parse command-line options."""
    default_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(
        description="Интерактивно закоммитить, запушить и затегировать Git-репозитории."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=default_root,
        help=f"Папка с репозиториями (по умолчанию: {default_root})",
    )
    return parser.parse_args()


def main() -> int:
    """Run the coordinated interactive release."""
    arguments = parse_arguments()
    root = arguments.root.expanduser().resolve()
    if not root.is_dir():
        print(f"Папка не найдена: {root}", file=sys.stderr)
        return 2

    repositories = discover_repositories(root)
    if not repositories:
        print(f"В {root} не найдено Git-репозиториев.", file=sys.stderr)
        return 2

    selected: list[tuple[Path, bool]] = []
    for repository in repositories:
        status_output = captured_git(repository, "status", "--short", "--untracked-files=all")
        show_changes(repository, status_output)
        prompt = (
            "Добавить все изменения, создать коммит и опубликовать?"
            if status_output
            else "Опубликовать текущий HEAD и создать только тег?"
        )
        if ask_yes_no(prompt):
            selected.append((repository, bool(status_output)))

    if not selected:
        print("Ни один репозиторий не выбран.")
        return 0

    print("\nВыбраны репозитории:")
    for repository, has_changes in selected:
        suffix = "commit + push + tag" if has_changes else "push + tag"
        print(f"  - {repository.name}: {suffix}")
    if not ask_yes_no("Продолжить с выбранным набором?"):
        print("Отменено до изменения индекса и публикации.")
        return 0

    commit_message = required_input("Текст коммита: ")
    tag = required_input("Имя тега, например v0.2.1: ")
    remote_name = input("Имя remote [origin]: ").strip() or "origin"
    token = getpass.getpass("GitHub token (ввод скрыт): ").strip()
    if not token:
        print("Токен не может быть пустым.", file=sys.stderr)
        return 2

    succeeded: list[str] = []
    failed: list[str] = []
    with tempfile.TemporaryDirectory(prefix="murchalka-release-") as temporary_directory:
        askpass = create_askpass(Path(temporary_directory))
        authentication = (askpass, token)
        prepared: list[tuple[Path, bool, str, str]] = []
        print("\nПроверка credentials и возможности публикации без изменений...")
        for repository, has_changes in selected:
            try:
                branch, remote_url = preflight_repository(
                    repository,
                    has_changes,
                    tag,
                    remote_name,
                    authentication,
                )
                prepared.append((repository, has_changes, branch, remote_url))
            except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as exception:
                failed.append(repository.name)
                print(f"ОШИБКА ПРОВЕРКИ {repository.name}: {exception}", file=sys.stderr)

        if failed:
            del token
            print("\nПубликация отменена до git add и создания коммитов.", file=sys.stderr)
            print(f"Не прошли проверку: {', '.join(failed)}", file=sys.stderr)
            return 1

        for repository, has_changes, branch, remote_url in prepared:
            print(f"\n--- Публикация {repository.name} ---")
            try:
                publish_repository(
                    repository,
                    has_changes,
                    commit_message,
                    tag,
                    branch,
                    remote_url,
                    authentication,
                )
                succeeded.append(repository.name)
            except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as exception:
                failed.append(repository.name)
                print(f"ОШИБКА {repository.name}: {exception}", file=sys.stderr)
                if not ask_yes_no("Продолжить со следующим репозиторием?"):
                    break

    del token
    print("\nИтог:")
    print(f"  успешно: {', '.join(succeeded) if succeeded else 'нет'}")
    print(f"  с ошибкой: {', '.join(failed) if failed else 'нет'}")
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nОтменено пользователем.", file=sys.stderr)
        raise SystemExit(130) from None
