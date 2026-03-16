#!/usr/bin/env python3
"""
Convert a Chrome bookmarks folder into an Obsidian markdown note.

Usage:
    python3 chrome_bookmarks_to_note.py "Bookmarks Bar/股票-文章" \
        "/Users/liyang/Documents/Obsidian Vault/stock/Inbox"

    python3 chrome_bookmarks_to_note.py "股票-文章" \
        "/Users/liyang/Documents/Obsidian Vault/stock/Inbox" \
        --category Inbox --tags 收藏夹,股票,文章
"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import re
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import TypedDict, cast
from urllib.parse import urlparse


DEFAULT_BOOKMARKS_FILE = Path(
    "~/Library/Application Support/Google/Chrome/Default/Bookmarks"
).expanduser()

ROOT_LABELS = {
    "bookmark_bar": "Bookmarks Bar",
    "other": "Other Bookmarks",
    "synced": "Mobile Bookmarks",
}

DEFAULT_TOPIC_RULES_FILE = (
    Path(__file__).resolve().parent.parent / "config" / "topic_rules.json"
)
DEFAULT_LLM_BASE_URL = "https://api.openai.com/v1"
DEFAULT_LLM_MODEL = "gpt-4o-mini"


class BookmarkNode(TypedDict, total=False):
    type: str
    name: str
    url: str
    children: list["BookmarkNode"]


class BookmarksData(TypedDict):
    roots: dict[str, BookmarkNode]


@dataclass
class FolderMatch:
    node: BookmarkNode
    path: list[str]


@dataclass
class TopicRules:
    source_path: Path
    unclassified_topic: str
    topic_rules: list[tuple[str, tuple[str, ...]]]
    series_patterns: list[tuple[str, re.Pattern[str]]]
    topic_rules_raw: list[tuple[str, list[str]]]
    series_patterns_raw: list[tuple[str, str]]


@dataclass
class LLMGroupingResult:
    groups: list[tuple[str, list[BookmarkNode]]]
    topic_keywords: dict[str, set[str]]


def normalize_text(value: str) -> str:
    return re.sub(r"\s+", "", value).lower()


def keyword_matches_title(keyword: str, title: str, compact_title: str) -> bool:
    normalized_keyword = normalize_text(keyword)
    if not normalized_keyword:
        return False

    if re.fullmatch(r"[a-z0-9.+#_-]+", normalized_keyword):
        if len(normalized_keyword) <= 3:
            boundary_pattern = re.compile(
                rf"(?<![a-z0-9]){re.escape(normalized_keyword)}(?![a-z0-9])"
            )
            return boundary_pattern.search(title.lower()) is not None
        return normalized_keyword in compact_title

    return normalized_keyword in compact_title


def split_path(value: str) -> list[str]:
    return [segment.strip() for segment in value.split("/") if segment.strip()]


def node_type(node: BookmarkNode) -> str:
    value = node.get("type")
    return value if isinstance(value, str) else ""


def node_name(node: BookmarkNode, fallback: str = "") -> str:
    value = node.get("name")
    if isinstance(value, str):
        return value
    return fallback


def node_url(node: BookmarkNode) -> str:
    value = node.get("url")
    return value if isinstance(value, str) else ""


def node_children(node: BookmarkNode) -> list[BookmarkNode]:
    value = node.get("children")
    if isinstance(value, list):
        return value
    return []


def normalize_node(raw: object) -> BookmarkNode | None:
    if not isinstance(raw, dict):
        return None

    raw_dict = cast(dict[object, object], raw)

    node: BookmarkNode = {}

    raw_type = raw_dict.get("type")
    if isinstance(raw_type, str):
        node["type"] = raw_type

    raw_name = raw_dict.get("name")
    if isinstance(raw_name, str):
        node["name"] = raw_name

    raw_url = raw_dict.get("url")
    if isinstance(raw_url, str):
        node["url"] = raw_url

    raw_children = raw_dict.get("children")
    if isinstance(raw_children, list):
        child_items = cast(list[object], raw_children)
        children: list[BookmarkNode] = []
        for item in child_items:
            child = normalize_node(item)
            if child is not None:
                children.append(child)
        if children:
            node["children"] = children

    return node


def load_bookmarks(path: Path) -> BookmarksData:
    try:
        raw_obj = cast(object, json.loads(path.read_text(encoding="utf-8")))
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid bookmarks JSON: {exc}") from exc

    if not isinstance(raw_obj, dict):
        raise ValueError("invalid bookmarks JSON: root is not an object")
    raw_dict = cast(dict[object, object], raw_obj)

    raw_roots_obj = raw_dict.get("roots")
    if not isinstance(raw_roots_obj, dict):
        raise ValueError("invalid bookmarks JSON: missing roots object")
    raw_roots = cast(dict[object, object], raw_roots_obj)

    roots: dict[str, BookmarkNode] = {}
    for key_obj, raw_node in raw_roots.items():
        if not isinstance(key_obj, str):
            continue
        key = key_obj
        node = normalize_node(raw_node)
        if node is None:
            continue
        if node_type(node) != "folder":
            continue
        roots[key] = node

    if not roots:
        raise ValueError("no valid root folders found in bookmarks JSON")

    return {"roots": roots}


def load_topic_rules(path: Path) -> TopicRules:
    if not path.is_file():
        raise ValueError(f"topic rules file not found: {path}")

    try:
        raw_obj = cast(object, json.loads(path.read_text(encoding="utf-8")))
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid topic rules JSON: {exc}") from exc

    if not isinstance(raw_obj, dict):
        raise ValueError("invalid topic rules JSON: root is not an object")
    raw_dict = cast(dict[object, object], raw_obj)

    raw_unclassified = raw_dict.get("unclassified_topic")
    if not isinstance(raw_unclassified, str) or not raw_unclassified.strip():
        raise ValueError("topic rules missing non-empty 'unclassified_topic'")
    unclassified_topic = raw_unclassified.strip()

    raw_topic_rules_obj = raw_dict.get("topic_rules")
    if not isinstance(raw_topic_rules_obj, list):
        raise ValueError("topic rules missing 'topic_rules' list")
    raw_topic_rules = cast(list[object], raw_topic_rules_obj)

    topic_rules: list[tuple[str, tuple[str, ...]]] = []
    topic_rules_raw: list[tuple[str, list[str]]] = []
    for index, item_obj in enumerate(raw_topic_rules):
        if not isinstance(item_obj, dict):
            raise ValueError(f"topic_rules[{index}] must be an object")
        item = cast(dict[object, object], item_obj)

        raw_topic = item.get("topic")
        if not isinstance(raw_topic, str) or not raw_topic.strip():
            raise ValueError(f"topic_rules[{index}].topic must be non-empty string")
        topic = raw_topic.strip()

        raw_keywords_obj = item.get("keywords")
        if not isinstance(raw_keywords_obj, list):
            raise ValueError(f"topic_rules[{index}].keywords must be a list")
        raw_keywords = cast(list[object], raw_keywords_obj)

        keywords: list[str] = []
        for keyword_obj in raw_keywords:
            if not isinstance(keyword_obj, str):
                raise ValueError(f"topic_rules[{index}].keywords contains non-string")
            keyword = keyword_obj.strip()
            if keyword:
                keywords.append(keyword)

        if not keywords:
            raise ValueError(f"topic_rules[{index}] has no valid keywords")

        topic_rules.append((topic, tuple(keywords)))
        topic_rules_raw.append((topic, list(keywords)))

    raw_series_obj = raw_dict.get("series_patterns")
    if not isinstance(raw_series_obj, list):
        raise ValueError("topic rules missing 'series_patterns' list")
    raw_series_patterns = cast(list[object], raw_series_obj)

    series_patterns: list[tuple[str, re.Pattern[str]]] = []
    series_patterns_raw: list[tuple[str, str]] = []
    for index, item_obj in enumerate(raw_series_patterns):
        if not isinstance(item_obj, dict):
            raise ValueError(f"series_patterns[{index}] must be an object")
        item = cast(dict[object, object], item_obj)

        raw_topic = item.get("topic")
        if not isinstance(raw_topic, str) or not raw_topic.strip():
            raise ValueError(f"series_patterns[{index}].topic must be non-empty string")
        topic = raw_topic.strip()

        raw_pattern = item.get("pattern")
        if not isinstance(raw_pattern, str) or not raw_pattern.strip():
            raise ValueError(
                f"series_patterns[{index}].pattern must be non-empty string"
            )

        try:
            pattern = re.compile(raw_pattern)
        except re.error as exc:
            raise ValueError(
                f"invalid regex in series_patterns[{index}]: {exc}"
            ) from exc

        series_patterns.append((topic, pattern))
        series_patterns_raw.append((topic, raw_pattern))

    if not topic_rules and not series_patterns:
        raise ValueError("topic rules must define at least one rule")

    return TopicRules(
        source_path=path,
        unclassified_topic=unclassified_topic,
        topic_rules=topic_rules,
        series_patterns=series_patterns,
        topic_rules_raw=topic_rules_raw,
        series_patterns_raw=series_patterns_raw,
    )


def save_topic_rules(rules: TopicRules) -> None:
    payload = {
        "unclassified_topic": rules.unclassified_topic,
        "series_patterns": [
            {"topic": topic, "pattern": pattern}
            for topic, pattern in rules.series_patterns_raw
        ],
        "topic_rules": [
            {"topic": topic, "keywords": keywords}
            for topic, keywords in rules.topic_rules_raw
        ],
    }
    serialized = json.dumps(payload, ensure_ascii=False, indent=2)
    _ = rules.source_path.write_text(serialized + "\n", encoding="utf-8")


def normalize_topic_key(value: str) -> str:
    return normalize_text(value)


def refresh_compiled_topic_rules(rules: TopicRules) -> None:
    rules.topic_rules = [
        (topic, tuple(keywords)) for topic, keywords in rules.topic_rules_raw
    ]
    rules.series_patterns = [
        (topic, re.compile(pattern)) for topic, pattern in rules.series_patterns_raw
    ]


def merge_rules_from_llm(
    rules: TopicRules,
    llm_keywords: dict[str, set[str]],
    min_keyword_length: int = 2,
) -> tuple[int, int]:
    topic_index: dict[str, int] = {}
    for idx, (topic, _keywords) in enumerate(rules.topic_rules_raw):
        topic_index[normalize_topic_key(topic)] = idx

    added_topics = 0
    added_keywords = 0

    for topic_name, keyword_set in llm_keywords.items():
        topic = topic_name.strip()
        if not topic:
            continue
        if normalize_topic_key(topic) == normalize_topic_key(rules.unclassified_topic):
            continue

        cleaned_keywords: list[str] = []
        seen_keywords: set[str] = set()
        for keyword in keyword_set:
            compact = " ".join(keyword.strip().split())
            if not compact:
                continue
            normalized = normalize_text(compact)
            if len(normalized) < min_keyword_length:
                continue
            if normalized in seen_keywords:
                continue
            seen_keywords.add(normalized)
            cleaned_keywords.append(compact)

        if not cleaned_keywords:
            continue

        normalized_topic = normalize_topic_key(topic)
        if normalized_topic in topic_index:
            idx = topic_index[normalized_topic]
            existing_topic, existing_keywords = rules.topic_rules_raw[idx]
            existing_normalized = {normalize_text(item) for item in existing_keywords}
            for keyword in cleaned_keywords:
                normalized = normalize_text(keyword)
                if normalized in existing_normalized:
                    continue
                existing_keywords.append(keyword)
                existing_normalized.add(normalized)
                added_keywords += 1
            rules.topic_rules_raw[idx] = (existing_topic, existing_keywords)
            continue

        rules.topic_rules_raw.append((topic, cleaned_keywords))
        topic_index[normalized_topic] = len(rules.topic_rules_raw) - 1
        added_topics += 1
        added_keywords += len(cleaned_keywords)

    if added_topics or added_keywords:
        refresh_compiled_topic_rules(rules)

    return added_topics, added_keywords


def root_label(root_key: str, root_node: BookmarkNode) -> str:
    custom_name = node_name(root_node).strip()
    if custom_name:
        return custom_name
    return ROOT_LABELS.get(root_key, root_key)


def walk_folders(node: BookmarkNode, current_path: list[str]) -> list[FolderMatch]:
    matches: list[FolderMatch] = []
    if node_type(node) == "folder":
        matches.append(FolderMatch(node=node, path=current_path))

    for child in node_children(node):
        if node_type(child) != "folder":
            continue
        child_name = node_name(child).strip()
        if not child_name:
            continue
        matches.extend(walk_folders(child, [*current_path, child_name]))

    return matches


def list_all_folders(bookmarks_data: BookmarksData) -> list[FolderMatch]:
    all_folders: list[FolderMatch] = []
    for root_key, root_node in bookmarks_data["roots"].items():
        all_folders.extend(walk_folders(root_node, [root_label(root_key, root_node)]))
    return all_folders


def path_endswith(full_path: list[str], tail_path: list[str]) -> bool:
    if len(tail_path) > len(full_path):
        return False
    normalized_full = [normalize_text(x) for x in full_path]
    normalized_tail = [normalize_text(x) for x in tail_path]
    return normalized_full[-len(normalized_tail) :] == normalized_tail


def find_target_folder(bookmarks_data: BookmarksData, folder_query: str) -> FolderMatch:
    query_parts = split_path(folder_query)
    if not query_parts:
        raise ValueError("folder query is empty")

    all_folders = list_all_folders(bookmarks_data)
    if not all_folders:
        raise ValueError("no bookmark folders found in bookmarks file")

    normalized_query = [normalize_text(x) for x in query_parts]

    exact_matches = [
        item
        for item in all_folders
        if [normalize_text(x) for x in item.path] == normalized_query
    ]
    if len(exact_matches) == 1:
        return exact_matches[0]
    if len(exact_matches) > 1:
        candidates = "\n".join(f"- {' / '.join(item.path)}" for item in exact_matches)
        raise ValueError(
            f"folder query is ambiguous (exact matches). Use a more specific path:\n{candidates}"
        )

    suffix_matches = [
        item for item in all_folders if path_endswith(item.path, query_parts)
    ]
    if len(suffix_matches) == 1:
        return suffix_matches[0]

    if not suffix_matches:
        raise ValueError(f"folder not found: {folder_query}")

    preview = "\n".join(f"- {' / '.join(item.path)}" for item in suffix_matches[:10])
    more = len(suffix_matches) - 10
    if more > 0:
        preview += f"\n- ... and {more} more"

    raise ValueError(
        f"folder query is ambiguous. Use full path, e.g. 'Bookmarks Bar/FolderName'.\nCandidates:\n{preview}"
    )


def looks_like_separator(node: BookmarkNode) -> bool:
    name = node_name(node).strip()
    url = node_url(node).strip()

    if "separator.mayastudios.com" in url:
        return True

    compact = re.sub(r"\s+", "", name)
    return bool(compact) and all(ch in "-─_=~·" for ch in compact)


def collect_stats(folder: BookmarkNode) -> tuple[int, int, int]:
    urls = 0
    separators = 0
    subfolders = 0

    for child in node_children(folder):
        child_type = node_type(child)
        if child_type == "url":
            if looks_like_separator(child):
                separators += 1
            else:
                urls += 1
        elif child_type == "folder":
            subfolders += 1
            child_urls, child_separators, child_subfolders = collect_stats(child)
            urls += child_urls
            separators += child_separators
            subfolders += child_subfolders

    return urls, separators, subfolders


def split_folder_children(
    folder: BookmarkNode,
) -> tuple[list[BookmarkNode], list[BookmarkNode]]:
    direct_urls = [
        child
        for child in node_children(folder)
        if node_type(child) == "url" and not looks_like_separator(child)
    ]
    child_folders = [
        child for child in node_children(folder) if node_type(child) == "folder"
    ]
    return direct_urls, child_folders


def is_unclassified_topic(topic: str, rules: TopicRules) -> bool:
    return normalize_topic_key(topic) == normalize_topic_key(rules.unclassified_topic)


def extract_json_block(text: str) -> str:
    start = text.find("{")
    end = text.rfind("}")
    if start < 0 or end < start:
        raise ValueError("LLM response does not contain a JSON object")
    return text[start : end + 1]


def call_openai_chat_completion(
    *,
    api_key: str,
    base_url: str,
    model: str,
    timeout_sec: int,
    system_prompt: str,
    user_payload: object,
) -> str:
    endpoint = base_url.rstrip("/") + "/chat/completions"
    parsed = urlparse(endpoint)
    if parsed.scheme not in {"http", "https"}:
        raise ValueError(f"Unsupported LLM base URL scheme: {parsed.scheme}")
    if not parsed.netloc:
        raise ValueError(f"Invalid LLM base URL: {base_url}")

    path = parsed.path or "/"
    if parsed.query:
        path = f"{path}?{parsed.query}"

    payload = {
        "model": model,
        "temperature": 0,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": json.dumps(user_payload, ensure_ascii=False)},
        ],
    }

    request_body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    }

    connection_cls = (
        http.client.HTTPSConnection
        if parsed.scheme == "https"
        else http.client.HTTPConnection
    )
    conn = connection_cls(parsed.netloc, timeout=timeout_sec)
    try:
        conn.request("POST", path, body=request_body, headers=headers)
        response = conn.getresponse()
        body = response.read().decode("utf-8", errors="replace")
    except OSError as exc:
        raise ValueError(f"LLM request failed: {exc}") from exc
    finally:
        conn.close()

    if response.status >= 400:
        raise ValueError(f"LLM request failed ({response.status}): {body}")

    response_text = body

    try:
        response_obj = cast(object, json.loads(response_text))
    except json.JSONDecodeError as exc:
        raise ValueError(f"LLM returned invalid JSON envelope: {exc}") from exc

    if not isinstance(response_obj, dict):
        raise ValueError("LLM returned invalid response envelope")
    response_dict = cast(dict[object, object], response_obj)

    choices_obj = response_dict.get("choices")
    if not isinstance(choices_obj, list) or not choices_obj:
        raise ValueError("LLM response missing choices")
    choices = cast(list[object], choices_obj)

    first_choice_obj = choices[0]
    if not isinstance(first_choice_obj, dict):
        raise ValueError("LLM response choice has invalid format")
    first_choice = cast(dict[object, object], first_choice_obj)

    message_obj = first_choice.get("message")
    if not isinstance(message_obj, dict):
        raise ValueError("LLM response missing message")
    message = cast(dict[object, object], message_obj)

    content_obj = message.get("content")
    if isinstance(content_obj, str):
        return content_obj

    if isinstance(content_obj, list):
        parts = cast(list[object], content_obj)
        text_parts: list[str] = []
        for part_obj in parts:
            if not isinstance(part_obj, dict):
                continue
            part = cast(dict[object, object], part_obj)
            text_obj = part.get("text")
            if isinstance(text_obj, str):
                text_parts.append(text_obj)
        if text_parts:
            return "".join(text_parts)

    raise ValueError("LLM response message content is empty")


def parse_llm_grouping_response(
    response_text: str,
    url_nodes: list[BookmarkNode],
    unclassified_topic: str,
) -> LLMGroupingResult:
    try:
        payload_obj = cast(object, json.loads(extract_json_block(response_text)))
    except json.JSONDecodeError as exc:
        raise ValueError(f"LLM grouping JSON parse failed: {exc}") from exc

    if not isinstance(payload_obj, dict):
        raise ValueError("LLM grouping response root must be an object")
    payload = cast(dict[object, object], payload_obj)

    raw_groups_obj = payload.get("groups")
    if not isinstance(raw_groups_obj, list):
        raise ValueError("LLM grouping response missing groups list")
    raw_groups = cast(list[object], raw_groups_obj)

    max_id = len(url_nodes)
    id_to_topic: dict[int, str] = {}
    topic_order: list[str] = []
    topic_keywords: dict[str, set[str]] = {}

    for group_obj in raw_groups:
        if not isinstance(group_obj, dict):
            continue
        group = cast(dict[object, object], group_obj)

        topic_obj = group.get("topic")
        if not isinstance(topic_obj, str):
            continue
        topic = topic_obj.strip()
        if not topic:
            continue

        if topic not in topic_order:
            topic_order.append(topic)

        item_ids_obj = group.get("item_ids")
        if isinstance(item_ids_obj, list):
            raw_ids = cast(list[object], item_ids_obj)
            for item_id_obj in raw_ids:
                if not isinstance(item_id_obj, int):
                    continue
                item_id = item_id_obj
                if item_id < 1 or item_id > max_id:
                    continue
                if item_id in id_to_topic:
                    continue
                id_to_topic[item_id] = topic

        keywords_obj = group.get("keywords")
        if isinstance(keywords_obj, list):
            raw_keywords = cast(list[object], keywords_obj)
            for keyword_obj in raw_keywords:
                if not isinstance(keyword_obj, str):
                    continue
                keyword = " ".join(keyword_obj.strip().split())
                if not keyword:
                    continue
                if topic not in topic_keywords:
                    topic_keywords[topic] = set()
                topic_keywords[topic].add(keyword)

    raw_unclassified_obj = payload.get("unclassified_item_ids")
    if isinstance(raw_unclassified_obj, list):
        raw_unclassified = cast(list[object], raw_unclassified_obj)
        for item_id_obj in raw_unclassified:
            if not isinstance(item_id_obj, int):
                continue
            item_id = item_id_obj
            if item_id < 1 or item_id > max_id:
                continue
            if item_id in id_to_topic:
                continue
            id_to_topic[item_id] = unclassified_topic

    for item_id in range(1, max_id + 1):
        if item_id not in id_to_topic:
            id_to_topic[item_id] = unclassified_topic

    grouped: dict[str, list[BookmarkNode]] = {}
    for item_id in range(1, max_id + 1):
        topic = id_to_topic[item_id]
        if topic not in grouped:
            grouped[topic] = []
        grouped[topic].append(url_nodes[item_id - 1])

    ordered_topics = [topic for topic in topic_order if topic in grouped]
    for topic in grouped.keys():
        if topic not in ordered_topics and topic != unclassified_topic:
            ordered_topics.append(topic)
    if unclassified_topic in grouped:
        ordered_topics.append(unclassified_topic)

    ordered_groups = [
        (topic, grouped[topic]) for topic in ordered_topics if grouped[topic]
    ]

    return LLMGroupingResult(groups=ordered_groups, topic_keywords=topic_keywords)


def llm_group_urls_by_topic(
    url_nodes: list[BookmarkNode],
    rules: TopicRules,
    *,
    llm_model: str,
    llm_api_key: str | None,
    llm_base_url: str,
    llm_timeout_sec: int,
    llm_response_file: str | None,
) -> LLMGroupingResult:
    items_payload = [
        {"id": index + 1, "title": node_name(node, "")}
        for index, node in enumerate(url_nodes)
    ]
    existing_topics = [topic for topic, _ in rules.series_patterns] + [
        topic for topic, _ in rules.topic_rules
    ]

    if llm_response_file:
        response_path = Path(llm_response_file).expanduser().resolve()
        if not response_path.is_file():
            raise ValueError(f"LLM response file not found: {response_path}")
        response_text = response_path.read_text(encoding="utf-8")
    else:
        if not llm_api_key:
            raise ValueError(
                "LLM API key is required for llm/hybrid mode. Set OPENAI_API_KEY or pass --llm-api-key."
            )

        system_prompt = (
            "You group bookmark titles into concise Chinese topics for knowledge notes. "
            "Return strict JSON only with schema: "
            '{"groups":[{"topic":"...","item_ids":[1,2],"keywords":["...","..."]}],'
            '"unclassified_item_ids":[3]}. '
            "Each item id appears at most once in groups. "
            "keywords should be short deterministic literals suitable for rule-engine substring matching."
        )
        user_payload = {
            "task": "Group bookmark titles and suggest deterministic keywords for each topic.",
            "existing_topics": existing_topics,
            "unclassified_topic": rules.unclassified_topic,
            "items": items_payload,
        }
        response_text = call_openai_chat_completion(
            api_key=llm_api_key,
            base_url=llm_base_url,
            model=llm_model,
            timeout_sec=llm_timeout_sec,
            system_prompt=system_prompt,
            user_payload=user_payload,
        )

    return parse_llm_grouping_response(
        response_text=response_text,
        url_nodes=url_nodes,
        unclassified_topic=rules.unclassified_topic,
    )


def append_or_merge_group(
    groups: list[tuple[str, list[BookmarkNode]]],
    topic: str,
    nodes: list[BookmarkNode],
) -> None:
    for idx, (existing_topic, existing_nodes) in enumerate(groups):
        if normalize_topic_key(existing_topic) != normalize_topic_key(topic):
            continue
        merged_nodes = [*existing_nodes, *nodes]
        groups[idx] = (existing_topic, merged_nodes)
        return
    groups.append((topic, list(nodes)))


def group_urls_by_mode(
    url_nodes: list[BookmarkNode],
    rules: TopicRules,
    *,
    group_mode: str,
    llm_model: str,
    llm_api_key: str | None,
    llm_base_url: str,
    llm_timeout_sec: int,
    llm_response_file: str | None,
) -> tuple[list[tuple[str, list[BookmarkNode]]], dict[str, set[str]]]:
    if group_mode == "rules":
        return group_urls_by_topic(url_nodes, rules), {}

    if group_mode == "llm":
        llm_result = llm_group_urls_by_topic(
            url_nodes,
            rules,
            llm_model=llm_model,
            llm_api_key=llm_api_key,
            llm_base_url=llm_base_url,
            llm_timeout_sec=llm_timeout_sec,
            llm_response_file=llm_response_file,
        )
        return llm_result.groups, llm_result.topic_keywords

    if group_mode == "hybrid":
        rule_groups = group_urls_by_topic(url_nodes, rules)
        merged_groups: list[tuple[str, list[BookmarkNode]]] = []
        unresolved: list[BookmarkNode] = []

        for topic, nodes in rule_groups:
            if is_unclassified_topic(topic, rules):
                unresolved.extend(nodes)
            else:
                merged_groups.append((topic, list(nodes)))

        if not unresolved:
            return merged_groups, {}

        llm_result = llm_group_urls_by_topic(
            unresolved,
            rules,
            llm_model=llm_model,
            llm_api_key=llm_api_key,
            llm_base_url=llm_base_url,
            llm_timeout_sec=llm_timeout_sec,
            llm_response_file=llm_response_file,
        )

        for topic, nodes in llm_result.groups:
            append_or_merge_group(merged_groups, topic, nodes)

        return merged_groups, llm_result.topic_keywords

    raise ValueError(f"unsupported group mode: {group_mode}")


def classify_topic(title: str, rules: TopicRules) -> str:
    compact = normalize_text(title)

    for topic, pattern in rules.series_patterns:
        if pattern.search(compact):
            return topic

    for topic, keywords in rules.topic_rules:
        for keyword in keywords:
            if keyword_matches_title(keyword, title, compact):
                return topic

    return rules.unclassified_topic


def group_urls_by_topic(
    url_nodes: list[BookmarkNode],
    rules: TopicRules,
) -> list[tuple[str, list[BookmarkNode]]]:
    grouped: dict[str, list[BookmarkNode]] = {}

    for node in url_nodes:
        topic = classify_topic(node_name(node, ""), rules)
        if topic not in grouped:
            grouped[topic] = []
        grouped[topic].append(node)

    ordered_topics = [topic for topic, _ in rules.series_patterns] + [
        topic for topic, _ in rules.topic_rules
    ]
    ordered_topics.append(rules.unclassified_topic)

    result: list[tuple[str, list[BookmarkNode]]] = []
    seen: set[str] = set()

    for topic in ordered_topics:
        nodes = grouped.get(topic)
        if nodes:
            result.append((topic, nodes))
            seen.add(topic)

    for topic, nodes in grouped.items():
        if topic in seen:
            continue
        result.append((topic, nodes))

    return result


def escape_markdown_link_text(text: str) -> str:
    return text.replace("\\", "\\\\").replace("]", "\\]").replace("\n", " ")


def append_url_list(lines: list[str], url_nodes: list[BookmarkNode]) -> None:
    for node in url_nodes:
        name = escape_markdown_link_text(node_name(node, "未命名"))
        url = node_url(node).strip()
        if not url:
            continue
        lines.append(f"- [{name}]({url})")


def render_links(folder: BookmarkNode, lines: list[str], level: int) -> None:
    heading_level = min(max(level, 2), 4)
    lines.append(f"{'#' * heading_level} {node_name(folder, '未命名目录')}")
    lines.append("")

    urls = [
        child
        for child in node_children(folder)
        if node_type(child) == "url" and not looks_like_separator(child)
    ]
    for item in urls:
        name = escape_markdown_link_text(node_name(item, "未命名"))
        url = node_url(item).strip()
        if not url:
            continue
        lines.append(f"- [{name}]({url})")

    if urls:
        lines.append("")

    for child in node_children(folder):
        if node_type(child) != "folder":
            continue
        render_links(child, lines, level + 1)


def yaml_quote(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def build_note_content(
    folder: BookmarkNode,
    folder_path: list[str],
    note_title: str,
    category: str,
    tags: list[str],
    group_by_topic: bool,
    topic_rules: TopicRules,
    grouped_direct_urls: list[tuple[str, list[BookmarkNode]]] | None,
) -> str:
    today = date.today().isoformat()
    total_urls, separators, subfolder_count = collect_stats(folder)

    lines: list[str] = [
        "---",
        f"title: {yaml_quote(note_title)}",
        f"date: {today}",
        "tags:",
    ]

    for tag in tags:
        lines.append(f"  - {yaml_quote(tag)}")

    lines.extend(
        [
            f"category: {yaml_quote(category)}",
            "---",
            "",
            f"# {note_title}",
            "",
            f"> 来源：Chrome 收藏夹 `{' / '.join(folder_path)}`",
            f"> 统计：{total_urls} 个网址，{subfolder_count} 个子目录，跳过 {separators} 个分隔符",
            "",
        ]
    )

    direct_urls, child_folders = split_folder_children(folder)

    if not direct_urls and not child_folders:
        lines.append("_该目录下没有可导出的网址。_")
        lines.append("")
        return "\n".join(lines)

    if direct_urls:
        if grouped_direct_urls is not None:
            grouped_urls = grouped_direct_urls
            if len(grouped_urls) == 1 and is_unclassified_topic(
                grouped_urls[0][0], topic_rules
            ):
                lines.append("## 链接列表")
                lines.append("")
                append_url_list(lines, direct_urls)
                lines.append("")
            else:
                for topic, url_nodes in grouped_urls:
                    heading = (
                        "链接列表"
                        if is_unclassified_topic(topic, topic_rules)
                        else topic
                    )
                    lines.append(f"## {heading}")
                    lines.append("")
                    append_url_list(lines, url_nodes)
                    lines.append("")
        elif group_by_topic and not child_folders:
            grouped_urls = group_urls_by_topic(direct_urls, topic_rules)
            if len(grouped_urls) == 1 and is_unclassified_topic(
                grouped_urls[0][0], topic_rules
            ):
                lines.append("## 链接列表")
                lines.append("")
                append_url_list(lines, direct_urls)
                lines.append("")
            else:
                for topic, url_nodes in grouped_urls:
                    heading = (
                        "链接列表"
                        if is_unclassified_topic(topic, topic_rules)
                        else topic
                    )
                    lines.append(f"## {heading}")
                    lines.append("")
                    append_url_list(lines, url_nodes)
                    lines.append("")
        else:
            lines.append("## 链接列表")
            lines.append("")
            append_url_list(lines, direct_urls)
            lines.append("")

    for subfolder in child_folders:
        render_links(subfolder, lines, level=2)

    return "\n".join(lines).rstrip() + "\n"


def parse_tags(raw: str) -> list[str]:
    tags = [part.strip() for part in raw.split(",") if part.strip()]
    return tags if tags else ["收藏夹", "chrome-bookmarks"]


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert a Chrome bookmarks folder into an Obsidian markdown note"
    )
    _ = parser.add_argument(
        "folder",
        help="Bookmark folder name or path (e.g. 股票-文章 or Bookmarks Bar/股票-文章)",
    )
    _ = parser.add_argument("output_dir", help="Output directory for the markdown note")
    _ = parser.add_argument(
        "--bookmarks-file",
        default=str(DEFAULT_BOOKMARKS_FILE),
        help="Path to Chrome Bookmarks JSON file",
    )
    _ = parser.add_argument(
        "--note-name",
        default=None,
        help="Override note filename/title (without .md)",
    )
    _ = parser.add_argument(
        "--category",
        default=None,
        help="Frontmatter category (default: output directory name)",
    )
    _ = parser.add_argument(
        "--tags",
        default="收藏夹,chrome-bookmarks",
        help="Comma-separated frontmatter tags",
    )
    _ = parser.add_argument(
        "--group-by-topic",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Group flat bookmark lists by topic (default: enabled)",
    )
    _ = parser.add_argument(
        "--group-mode",
        choices=["rules", "llm", "hybrid"],
        default="hybrid",
        help="Topic grouping mode when --group-by-topic is enabled",
    )
    _ = parser.add_argument(
        "--learn-rules",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Learn and merge new keyword rules from LLM grouping output",
    )
    _ = parser.add_argument(
        "--topic-rules-file",
        default=str(DEFAULT_TOPIC_RULES_FILE),
        help="Path to topic rules JSON file",
    )
    _ = parser.add_argument(
        "--llm-model",
        default=os.environ.get("OPENAI_MODEL", DEFAULT_LLM_MODEL),
        help="LLM model name for llm/hybrid mode",
    )
    _ = parser.add_argument(
        "--llm-base-url",
        default=os.environ.get("OPENAI_BASE_URL", DEFAULT_LLM_BASE_URL),
        help="OpenAI-compatible base URL",
    )
    _ = parser.add_argument(
        "--llm-api-key",
        default=os.environ.get("OPENAI_API_KEY"),
        help="OpenAI-compatible API key",
    )
    _ = parser.add_argument(
        "--llm-timeout-sec",
        type=int,
        default=60,
        help="LLM request timeout in seconds",
    )
    _ = parser.add_argument(
        "--llm-response-file",
        default=None,
        help="Local JSON response file for offline LLM simulation",
    )
    _ = parser.add_argument(
        "--dry-run-llm",
        action="store_true",
        default=False,
        help="Run rules matching, dump unclassified items as JSON, then exit",
    )

    args = parser.parse_args()
    folder_query = cast(str, args.folder)
    output_dir_arg = cast(str, args.output_dir)
    bookmarks_file_arg = cast(str, args.bookmarks_file)
    note_name_arg = cast(str | None, args.note_name)
    category_arg = cast(str | None, args.category)
    tags_arg = cast(str, args.tags)
    group_by_topic_arg = cast(bool, args.group_by_topic)
    group_mode_arg = cast(str, args.group_mode)
    learn_rules_arg = cast(bool, args.learn_rules)
    topic_rules_file_arg = cast(str, args.topic_rules_file)
    llm_model_arg = cast(str, args.llm_model)
    llm_base_url_arg = cast(str, args.llm_base_url)
    llm_api_key_arg = cast(str | None, args.llm_api_key)
    llm_timeout_sec_arg = cast(int, args.llm_timeout_sec)
    llm_response_file_arg = cast(str | None, args.llm_response_file)
    dry_run_llm_arg = cast(bool, args.dry_run_llm)

    bookmarks_path = Path(bookmarks_file_arg).expanduser().resolve()
    if not bookmarks_path.is_file():
        print(f"Error: bookmarks file not found: {bookmarks_path}", file=sys.stderr)
        sys.exit(1)

    output_dir = Path(output_dir_arg).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        bookmarks_data = load_bookmarks(bookmarks_path)
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)

    try:
        target_folder = find_target_folder(bookmarks_data, folder_query)
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)

    topic_rules_path = Path(topic_rules_file_arg).expanduser().resolve()
    try:
        topic_rules = load_topic_rules(topic_rules_path)
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)

    note_name = note_name_arg or node_name(target_folder.node, "bookmarks").strip()
    if not note_name:
        note_name = "bookmarks"

    category = category_arg or output_dir.name
    tags = parse_tags(tags_arg)

    direct_urls, child_folders = split_folder_children(target_folder.node)

    grouped_direct_urls: list[tuple[str, list[BookmarkNode]]] | None = None
    learned_topics = 0
    learned_keywords = 0

    if group_by_topic_arg and direct_urls and not child_folders:
        if dry_run_llm_arg and group_mode_arg in {"hybrid", "llm"}:
            if group_mode_arg == "hybrid":
                rule_groups = group_urls_by_topic(direct_urls, topic_rules)
                unresolved: list[BookmarkNode] = []
                for topic, nodes in rule_groups:
                    if is_unclassified_topic(topic, topic_rules):
                        unresolved.extend(nodes)
                items_to_group = unresolved
            else:
                items_to_group = direct_urls

            existing_topics = [t for t, _ in topic_rules.series_patterns] + [
                t for t, _ in topic_rules.topic_rules
            ]
            items_payload = [
                {"id": idx + 1, "title": node_name(node, "")}
                for idx, node in enumerate(items_to_group)
            ]
            dry_run_output = {
                "existing_topics": existing_topics,
                "unclassified_topic": topic_rules.unclassified_topic,
                "items": items_payload,
                "total_bookmarks": len(direct_urls),
                "rules_classified": len(direct_urls) - len(items_to_group),
                "needs_classification": len(items_to_group),
                "expected_response_schema": {
                    "groups": [
                        {
                            "topic": "主题名",
                            "item_ids": [1, 2],
                            "keywords": ["关键词1"],
                        }
                    ],
                    "unclassified_item_ids": [3],
                },
            }
            print(json.dumps(dry_run_output, ensure_ascii=False, indent=2))
            sys.exit(0)

        try:
            grouped_direct_urls, llm_keywords = group_urls_by_mode(
                direct_urls,
                topic_rules,
                group_mode=group_mode_arg,
                llm_model=llm_model_arg,
                llm_api_key=llm_api_key_arg,
                llm_base_url=llm_base_url_arg,
                llm_timeout_sec=llm_timeout_sec_arg,
                llm_response_file=llm_response_file_arg,
            )
        except ValueError as exc:
            print(f"Error: {exc}", file=sys.stderr)
            sys.exit(1)

        if learn_rules_arg and group_mode_arg in {"llm", "hybrid"}:
            learned_topics, learned_keywords = merge_rules_from_llm(
                topic_rules,
                llm_keywords,
            )
            if learned_topics or learned_keywords:
                save_topic_rules(topic_rules)

    note_content = build_note_content(
        folder=target_folder.node,
        folder_path=target_folder.path,
        note_title=note_name,
        category=category,
        tags=tags,
        group_by_topic=group_by_topic_arg,
        topic_rules=topic_rules,
        grouped_direct_urls=grouped_direct_urls,
    )

    output_file = output_dir / f"{note_name}.md"
    _ = output_file.write_text(note_content, encoding="utf-8")

    total_urls, separators, subfolder_count = collect_stats(target_folder.node)
    print(f"Folder: {' / '.join(target_folder.path)}")
    print(f"Bookmarks: {total_urls}")
    print(f"Subfolders: {subfolder_count}")
    print(f"Separators skipped: {separators}")
    if group_by_topic_arg:
        mode_label = group_mode_arg if grouped_direct_urls is not None else "rules"
        print(f"Group mode: {mode_label}")
    if learned_topics or learned_keywords:
        print(
            f"Rules learned: +{learned_topics} topic(s), +{learned_keywords} keyword(s)"
        )
        print(f"Rules file updated: {topic_rules.source_path}")
    print(f"Output: {output_file}")


if __name__ == "__main__":
    main()
