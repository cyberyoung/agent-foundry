#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCRIPT_PATH = Path(__file__).resolve()
SCRIPT_DIR = SCRIPT_PATH.parent
SKILL_BASE_DIR = SCRIPT_DIR.parent
NAMESPACE_ROOT = SKILL_BASE_DIR.parent
SKILLS_ROOT = NAMESPACE_ROOT.parent
AGENTS_ROOT = SKILLS_ROOT.parent
REGISTRY_PATH = SKILL_BASE_DIR / "upstream-registry.json"
SYNC_SCRIPT = SKILLS_ROOT / "skill-management/sync-skills/scripts/sync.sh"
BACKUP_ROOT = SKILL_BASE_DIR / ".backups"
AGENT_TARGETS: dict[str, Path] = {
    "claude": Path.home() / ".claude/skills",
    "codex": Path.home() / ".codex/skills",
    "opencode": Path.home() / ".config/opencode/skills",
}


@dataclass
class UpstreamSpec:
    dest_name: str
    repo_input: str
    owner_repo: str
    clone_url: str
    upstream_skill: str
    source_path: str | None
    ref: str


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def normalize_repo(repo_input: str) -> tuple[str, str]:
    text = repo_input.strip()
    match = re.search(r"github\.com[:/]([^/]+)/([^/.]+)(?:\.git)?(?:/.*)?$", text)
    if match:
        owner_repo = f"{match.group(1)}/{match.group(2)}"
        return owner_repo, f"https://github.com/{owner_repo}.git"
    match = re.fullmatch(r"([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)", text)
    if match:
        owner_repo = f"{match.group(1)}/{match.group(2)}"
        return owner_repo, f"https://github.com/{owner_repo}.git"
    raise ValueError(f"Unsupported repo format: {repo_input}")


def run_cmd(args: list[str], cwd: Path | None = None) -> None:
    _ = subprocess.run(args, cwd=str(cwd) if cwd else None, check=True)


def load_registry() -> dict[str, dict[str, str]]:
    if not REGISTRY_PATH.exists():
        return {}
    data = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"Invalid registry format: {REGISTRY_PATH}")
    result: dict[str, dict[str, str]] = {}
    for key, value in data.items():
        if isinstance(key, str) and isinstance(value, dict):
            normalized: dict[str, str] = {}
            for field_key, field_value in value.items():
                if isinstance(field_key, str) and isinstance(field_value, str):
                    normalized[field_key] = field_value
            result[key] = normalized
    return result


def save_registry(data: dict[str, dict[str, str]]) -> None:
    REGISTRY_PATH.parent.mkdir(parents=True, exist_ok=True)
    REGISTRY_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def parse_skill_name_and_description(
    skill_md_path: Path,
) -> tuple[str | None, str | None]:
    text = skill_md_path.read_text(encoding="utf-8")
    name_match = re.search(r"^name:\s*(.+?)\s*$", text, flags=re.MULTILINE)
    desc_match = re.search(r"^description:\s*(.+?)\s*$", text, flags=re.MULTILINE)
    name = name_match.group(1).strip() if name_match else None
    description = desc_match.group(1).strip() if desc_match else None
    return name, description


def discover_skills() -> list[dict[str, Any]]:
    registry = load_registry()
    discovered: list[dict[str, Any]] = []
    for entry in sorted(SKILLS_ROOT.iterdir()):
        if not entry.is_dir():
            continue
        if (entry / ".prefix").exists():
            prefix = (entry / ".prefix").read_text(encoding="utf-8").strip()
            if not prefix:
                continue
            for child in sorted(entry.iterdir()):
                if not child.is_dir():
                    continue
                skill_md = child / "SKILL.md"
                if not skill_md.exists():
                    continue
                local_dir_name = child.name
                exposed_name = f"{prefix}-{local_dir_name}"
                reg = registry.get(local_dir_name, {})
                source_type = "upstream" if reg else "local"
                source_url = reg.get("repo_input")
                skill_name, description = parse_skill_name_and_description(skill_md)
                discovered.append(
                    {
                        "local_dir": local_dir_name,
                        "source_dir": str(child),
                        "exposed_name": exposed_name,
                        "namespace": entry.name,
                        "source_type": source_type,
                        "source_url": source_url,
                        "skill_name": skill_name,
                        "description": description,
                        "registry": reg,
                    }
                )
            continue

        skill_md = entry / "SKILL.md"
        if not skill_md.exists():
            continue
        local_dir_name = entry.name
        reg = registry.get(local_dir_name, {})
        source_type = "upstream" if reg else "local"
        source_url = reg.get("repo_input")
        skill_name, description = parse_skill_name_and_description(skill_md)
        discovered.append(
            {
                "local_dir": local_dir_name,
                "source_dir": str(entry),
                "exposed_name": local_dir_name,
                "namespace": None,
                "source_type": source_type,
                "source_url": source_url,
                "skill_name": skill_name,
                "description": description,
                "registry": reg,
            }
        )
    return discovered


def sync_state_for_skill(
    source_dir: Path, exposed_name: str
) -> dict[str, dict[str, Any]]:
    expected_target = str(source_dir.resolve())
    result: dict[str, dict[str, Any]] = {}
    for agent, base in AGENT_TARGETS.items():
        link_path = base / exposed_name
        exists = link_path.exists() or link_path.is_symlink()
        is_symlink = link_path.is_symlink()
        current_target = str(link_path.resolve()) if is_symlink else None
        target_ok = is_symlink and current_target == expected_target
        result[agent] = {
            "path": str(link_path),
            "exists": exists,
            "is_symlink": is_symlink,
            "target_ok": target_ok,
            "current_target": current_target,
            "expected_target": expected_target,
        }
    return result


def print_status_table(items: list[dict[str, Any]], compact: bool = False) -> None:
    if not items:
        print("No skills discovered in skills root")
        return

    def short_url(value: str | None) -> str:
        if not value:
            return "-"
        return value if len(value) <= 42 else value[:39] + "..."

    rows: list[dict[str, str]] = []
    for item in items:
        sync_state = item["sync_state"]
        base_row = {
            "skill": str(item["exposed_name"]),
            "source": str(item["source_type"]),
            "ref": str(item.get("registry", {}).get("ref", "-")),
            "source_url": short_url(item.get("source_url")),
            "claude": "ok" if sync_state["claude"]["target_ok"] else "drift",
            "codex": "ok" if sync_state["codex"]["target_ok"] else "drift",
            "opencode": "ok" if sync_state["opencode"]["target_ok"] else "drift",
        }
        if compact:
            rows.append(
                {
                    "skill": base_row["skill"],
                    "source": base_row["source"],
                    "ref": base_row["ref"],
                    "claude": base_row["claude"],
                    "codex": base_row["codex"],
                    "opencode": base_row["opencode"],
                }
            )
        else:
            rows.append(base_row)

    headers = (
        ["skill", "source", "ref", "claude", "codex", "opencode"]
        if compact
        else [
            "skill",
            "source",
            "ref",
            "source_url",
            "claude",
            "codex",
            "opencode",
        ]
    )
    widths = {key: max(len(key), max(len(row[key]) for row in rows)) for key in headers}

    def format_row(row: dict[str, str]) -> str:
        return " | ".join(row[key].ljust(widths[key]) for key in headers)

    header_row = {key: key for key in headers}
    sep_row = {key: "-" * widths[key] for key in headers}
    print(format_row(header_row))
    print(format_row(sep_row))
    for row in rows:
        print(format_row(row))


def command_status(args: argparse.Namespace) -> None:
    items = discover_skills()
    if bool(args.upstream_only):
        items = [item for item in items if item["source_type"] == "upstream"]
    if bool(args.local_only):
        items = [item for item in items if item["source_type"] == "local"]
    for item in items:
        item["sync_state"] = sync_state_for_skill(
            Path(item["source_dir"]), item["exposed_name"]
        )
    if args.json:
        print(json.dumps(items, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print_status_table(items, compact=bool(args.compact))


def command_verify(args: argparse.Namespace) -> None:
    failures: list[str] = []
    warnings: list[str] = []
    items = discover_skills()
    for item in items:
        source_dir = Path(item["source_dir"])
        skill_md = source_dir / "SKILL.md"
        if not skill_md.exists():
            failures.append(f"{item['exposed_name']}: missing SKILL.md")
            continue
        if item["skill_name"] is None:
            warnings.append(f"{item['exposed_name']}: missing frontmatter name")
        if item["description"] is None:
            warnings.append(f"{item['exposed_name']}: missing frontmatter description")

        sync_state = sync_state_for_skill(source_dir, item["exposed_name"])
        for agent, state in sync_state.items():
            if not state["target_ok"]:
                failures.append(f"{item['exposed_name']}: {agent} sync drift")

    if failures:
        if args.json:
            print(
                json.dumps(
                    {"ok": False, "failures": failures}, ensure_ascii=False, indent=2
                )
            )
        else:
            print("VERIFY FAILED")
            for failure in failures:
                print(f"- {failure}")
            if warnings:
                print("WARNINGS")
                for warning in warnings:
                    print(f"- {warning}")
        raise SystemExit(1)

    if args.json:
        print(
            json.dumps(
                {"ok": True, "count": len(items), "warnings": warnings},
                ensure_ascii=False,
                indent=2,
            )
        )
    else:
        print("VERIFY PASSED")
        print(f"- skills: {len(items)}")
        if warnings:
            print("WARNINGS")
            for warning in warnings:
                print(f"- {warning}")


def resolve_source_dir(
    repo_root: Path, upstream_skill: str, source_path: str | None
) -> tuple[Path, str]:
    candidates: list[Path] = []
    if source_path and source_path != ".":
        candidates.append(repo_root / source_path)
    else:
        candidates.append(repo_root / "skills" / upstream_skill)
        candidates.append(repo_root / upstream_skill)
    candidates.append(repo_root)
    for candidate in candidates:
        if candidate.is_dir() and (candidate / "SKILL.md").exists():
            rel = candidate.relative_to(repo_root).as_posix()
            return candidate, rel if rel != "." else ""
    names = ", ".join(str(p.relative_to(repo_root)) for p in candidates)
    raise FileNotFoundError(f"No valid skill directory found. Checked: {names}")


def prepare_repo(clone_url: str, ref: str) -> Path:
    temp_dir = Path(tempfile.mkdtemp(prefix="skill-install-"))
    repo_root = temp_dir / "repo"
    run_cmd(["git", "clone", clone_url, str(repo_root)])
    run_cmd(["git", "checkout", ref], cwd=repo_root)
    return repo_root


def replace_dir_atomically(
    source_dir: Path, target_dir: Path, allow_replace: bool
) -> None:
    BACKUP_ROOT.mkdir(parents=True, exist_ok=True)
    backup_dir = BACKUP_ROOT / f"{target_dir.name}-{int(datetime.now().timestamp())}"
    had_target = target_dir.exists()
    if had_target and not allow_replace:
        raise RuntimeError(f"Target exists: {target_dir}. Use --force to replace.")
    try:
        if had_target:
            target_dir.rename(backup_dir)
        shutil.copytree(source_dir, target_dir)
    except Exception as exc:
        if target_dir.exists():
            shutil.rmtree(target_dir)
        if backup_dir.exists():
            backup_dir.rename(target_dir)
        raise RuntimeError(f"Failed to replace {target_dir}: {exc}") from exc
    if backup_dir.exists():
        shutil.rmtree(backup_dir)


GITIGNORE_PATH = AGENTS_ROOT / ".gitignore"
GITIGNORE_MARKER = "# Upstream skills (installed via sm-lifecycle, auto-managed)"


def _ensure_gitignore(dest_name: str) -> None:
    gitignore_entry = f"skills/{dest_name}/"
    if not GITIGNORE_PATH.exists():
        return
    content = GITIGNORE_PATH.read_text(encoding="utf-8")
    if gitignore_entry in content:
        return
    lines = content.splitlines()
    try:
        marker_idx = lines.index(GITIGNORE_MARKER)
    except ValueError:
        lines.append("")
        lines.append(GITIGNORE_MARKER)
        marker_idx = len(lines) - 1
    insert_idx = marker_idx + 1
    while insert_idx < len(lines) and lines[insert_idx].startswith("skills/"):
        insert_idx += 1
    lines.insert(insert_idx, gitignore_entry)
    GITIGNORE_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _copy_and_register(
    source_dir: Path,
    dest_name: str,
    spec: UpstreamSpec,
    resolved_source_path: str,
    force: bool,
    collection: str | None = None,
) -> None:
    target_dir = SKILLS_ROOT / dest_name
    replace_dir_atomically(source_dir, target_dir, allow_replace=force)

    registry = load_registry()
    entry: dict[str, str] = {
        "source_type": "upstream",
        "repo_input": spec.repo_input,
        "owner_repo": spec.owner_repo,
        "clone_url": spec.clone_url,
        "upstream_skill": spec.upstream_skill,
        "source_path": resolved_source_path,
        "ref": spec.ref,
        "updated_at": now_iso(),
    }
    if collection:
        entry["collection"] = collection
    registry[dest_name] = entry
    save_registry(registry)

    _ensure_gitignore(dest_name)

    print(
        f"Installed: {dest_name} <- {spec.owner_repo}:{resolved_source_path}@{spec.ref}"
    )


def discover_skills_in_dir(base_dir: Path) -> list[tuple[Path, str, str]]:
    skills: list[tuple[Path, str, str]] = []
    for skill_md in sorted(base_dir.rglob("SKILL.md")):
        skill_dir = skill_md.parent
        if skill_dir == base_dir:
            continue
        rel_path = skill_dir.relative_to(base_dir).as_posix()
        skills.append((skill_dir, skill_dir.name, rel_path))
    return skills


def install_one(spec: UpstreamSpec, sync_after: bool, force: bool) -> None:
    repo_root = prepare_repo(spec.clone_url, spec.ref)
    try:
        source_dir, resolved_source_path = resolve_source_dir(
            repo_root, spec.upstream_skill, spec.source_path
        )
        _copy_and_register(
            source_dir, spec.dest_name, spec, resolved_source_path, force
        )
    finally:
        shutil.rmtree(repo_root.parent)

    if sync_after:
        run_cmd(["bash", str(SYNC_SCRIPT)])


def install_collection(spec: UpstreamSpec, sync_after: bool, force: bool) -> None:
    repo_root = prepare_repo(spec.clone_url, spec.ref)
    try:
        search_base = repo_root
        if spec.source_path and spec.source_path not in (".", ""):
            candidate = repo_root / spec.source_path
            if candidate.is_dir():
                search_base = candidate

        skills = discover_skills_in_dir(search_base)
        if not skills:
            raise FileNotFoundError(
                f"No skills found under {search_base.relative_to(repo_root)}"
            )

        print(f"Collection: {spec.owner_repo} ({len(skills)} skills)")
        for skill_dir, skill_name, _ in skills:
            resolved = skill_dir.relative_to(repo_root).as_posix()
            _copy_and_register(
                skill_dir,
                skill_name,
                spec,
                resolved,
                force,
                collection=spec.owner_repo,
            )
    finally:
        shutil.rmtree(repo_root.parent)

    if sync_after:
        run_cmd(["bash", str(SYNC_SCRIPT)])


def command_install(args: argparse.Namespace) -> None:
    owner_repo, clone_url = normalize_repo(str(args.repo))
    spec = UpstreamSpec(
        dest_name=str(args.dest_name) if args.dest_name else str(args.skill),
        repo_input=str(args.repo),
        owner_repo=owner_repo,
        clone_url=clone_url,
        upstream_skill=str(args.skill),
        source_path=str(args.source_path) if args.source_path else None,
        ref=str(args.ref),
    )
    sync_after = not bool(args.no_sync)
    force = bool(args.force)

    repo_root = prepare_repo(spec.clone_url, spec.ref)
    try:
        try:
            source_dir, resolved_source_path = resolve_source_dir(
                repo_root, spec.upstream_skill, spec.source_path
            )
            _copy_and_register(
                source_dir, spec.dest_name, spec, resolved_source_path, force
            )
        except FileNotFoundError:
            search_base = repo_root
            if spec.source_path and spec.source_path not in (".", ""):
                candidate = repo_root / spec.source_path
                if candidate.is_dir():
                    search_base = candidate
            skills = discover_skills_in_dir(search_base)
            if not skills:
                raise
            print(f"Collection: {spec.owner_repo} ({len(skills)} skills)")
            for skill_dir, skill_name, _ in skills:
                resolved = skill_dir.relative_to(repo_root).as_posix()
                _copy_and_register(
                    skill_dir,
                    skill_name,
                    spec,
                    resolved,
                    force,
                    collection=spec.owner_repo,
                )
    finally:
        shutil.rmtree(repo_root.parent)

    if sync_after:
        run_cmd(["bash", str(SYNC_SCRIPT)])


def command_update(args: argparse.Namespace) -> None:
    registry = load_registry()
    if not registry:
        print(f"No upstream skills tracked in {REGISTRY_PATH}")
        return
    targets: list[str]
    if args.collection:
        coll = str(args.collection)
        targets = sorted(
            name for name, item in registry.items() if item.get("collection") == coll
        )
        if not targets:
            raise KeyError(f"No skills found for collection: {coll}")
    elif args.skill:
        target = str(args.skill)
        if target not in registry:
            raise KeyError(f"Skill not tracked in registry: {target}")
        targets = [target]
    else:
        targets = sorted(registry.keys())

    for dest_name in targets:
        item = registry[dest_name]
        spec = UpstreamSpec(
            dest_name=dest_name,
            repo_input=item["repo_input"],
            owner_repo=item["owner_repo"],
            clone_url=item["clone_url"],
            upstream_skill=item["upstream_skill"],
            source_path=item.get("source_path"),
            ref=item.get("ref", "main"),
        )
        install_one(spec, sync_after=False, force=True)

    if not bool(args.no_sync):
        run_cmd(["bash", str(SYNC_SCRIPT)])

    print(f"Updated {len(targets)} skill(s)")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Unified local/upstream skill manager")
    subparsers = parser.add_subparsers(dest="command", required=True)

    parser_install = subparsers.add_parser("install", help="Install one upstream skill")
    _ = parser_install.add_argument(
        "--repo", required=True, help="GitHub URL or owner/repo"
    )
    _ = parser_install.add_argument(
        "--skill", required=True, help="Upstream skill directory name"
    )
    _ = parser_install.add_argument(
        "--source-path", help="Custom upstream path to the skill directory"
    )
    _ = parser_install.add_argument(
        "--dest-name", help="Local destination skill directory name"
    )
    _ = parser_install.add_argument(
        "--ref", default="main", help="Git ref, tag, or commit"
    )
    _ = parser_install.add_argument(
        "--force", action="store_true", help="Replace existing local directory"
    )
    _ = parser_install.add_argument(
        "--no-sync", action="store_true", help="Skip sync.sh after install"
    )
    parser_install.set_defaults(func=command_install)

    parser_update = subparsers.add_parser(
        "update", help="Update tracked upstream skills"
    )
    _ = parser_update.add_argument(
        "--skill", help="Update one tracked local skill name"
    )
    _ = parser_update.add_argument(
        "--collection",
        help="Update all skills from a collection (e.g. kepano/obsidian-skills)",
    )
    _ = parser_update.add_argument(
        "--no-sync", action="store_true", help="Skip sync.sh after update"
    )
    parser_update.set_defaults(func=command_update)

    parser_status = subparsers.add_parser(
        "status", help="Show local/upstream and sync status"
    )
    _ = parser_status.add_argument("--json", action="store_true", help="Output JSON")
    _ = parser_status.add_argument(
        "--compact", action="store_true", help="Hide source_url column"
    )
    status_source_group = parser_status.add_mutually_exclusive_group()
    _ = status_source_group.add_argument(
        "--upstream-only", action="store_true", help="Show only upstream skills"
    )
    _ = status_source_group.add_argument(
        "--local-only", action="store_true", help="Show only local skills"
    )
    parser_status.set_defaults(func=command_status)

    parser_verify = subparsers.add_parser(
        "verify", help="Verify skill metadata and sync consistency"
    )
    _ = parser_verify.add_argument("--json", action="store_true", help="Output JSON")
    parser_verify.set_defaults(func=command_verify)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
