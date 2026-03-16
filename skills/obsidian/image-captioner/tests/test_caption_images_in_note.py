import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = (
    Path(__file__).resolve().parents[1] / "scripts" / "caption_images_in_note.py"
)
SPEC = importlib.util.spec_from_file_location("caption_images_in_note", MODULE_PATH)
assert SPEC is not None
caption_images_in_note = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(caption_images_in_note)


class ParseEmbedsTests(unittest.TestCase):
    def test_parse_embeds_supports_common_obsidian_forms(self) -> None:
        note = "\n".join(
            [
                "![[image.png]]",
                "![[assets/image-4.png]]",
                "![[image.png|600]]",
                "  ![[folder/image.png|alias]]",
            ]
        )

        embeds = caption_images_in_note.parse_embeds(note)

        self.assertEqual(
            [embed["target"] for embed in embeds],
            [
                "image.png",
                "assets/image-4.png",
                "image.png",
                "folder/image.png",
            ],
        )
        self.assertEqual([embed["line_index"] for embed in embeds], [0, 1, 2, 3])
        self.assertEqual(embeds[3]["indent"], "  ")


class CaptionDetectionTests(unittest.TestCase):
    def test_bullet_after_embed_counts_as_caption(self) -> None:
        lines = ["![[image.png]]", "", "- 光纤图谱：说明文字"]
        self.assertTrue(caption_images_in_note.has_following_caption(lines, 0, ""))

    def test_short_paragraph_after_embed_counts_as_caption(self) -> None:
        lines = ["![[image.png]]", "", "这是一张产业链梳理图。"]
        self.assertTrue(caption_images_in_note.has_following_caption(lines, 0, ""))

    def test_separator_after_embed_means_missing_caption(self) -> None:
        lines = ["![[image.png]]", "", "----"]
        self.assertFalse(caption_images_in_note.has_following_caption(lines, 0, ""))

    def test_heading_after_embed_means_missing_caption(self) -> None:
        lines = ["![[image.png]]", "", "## Next"]
        self.assertFalse(caption_images_in_note.has_following_caption(lines, 0, ""))

    def test_indented_bullet_under_list_item_counts_as_caption(self) -> None:
        lines = ["1. ![[image.png]]", "   - 数据中心散热方案对比图：说明文字"]
        self.assertTrue(caption_images_in_note.has_following_caption(lines, 0, "   "))


class ResolutionAndApplyTests(unittest.TestCase):
    def test_resolve_image_path_prefers_note_relative_then_assets_then_vault_root(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            vault_root = Path(tmp_dir)
            note_dir = vault_root / "stock" / "调研笔记"
            note_dir.mkdir(parents=True)
            note_path = note_dir / "研报阅读.md"
            note_path.write_text("", encoding="utf-8")

            note_relative = note_dir / "image.png"
            note_relative.write_text("note", encoding="utf-8")
            assets_image = note_dir / "assets" / "image-2.png"
            assets_image.parent.mkdir(parents=True)
            assets_image.write_text("assets", encoding="utf-8")
            vault_relative = vault_root / "shared" / "image-3.png"
            vault_relative.parent.mkdir(parents=True)
            vault_relative.write_text("vault", encoding="utf-8")

            self.assertEqual(
                caption_images_in_note.resolve_image_path(
                    "image.png", note_path, vault_root
                ),
                note_relative,
            )
            self.assertEqual(
                caption_images_in_note.resolve_image_path(
                    "image-2.png", note_path, vault_root
                ),
                assets_image,
            )
            self.assertEqual(
                caption_images_in_note.resolve_image_path(
                    "shared/image-3.png", note_path, vault_root
                ),
                vault_relative,
            )

    def test_scan_note_marks_missing_images_without_aborting(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            vault_root = Path(tmp_dir)
            note_dir = vault_root / "stock" / "调研笔记"
            note_dir.mkdir(parents=True)
            note_path = note_dir / "研报阅读.md"
            note_path.write_text("![[missing.png]]\n\n----\n", encoding="utf-8")

            report = caption_images_in_note.scan_note(note_path, vault_root)

            self.assertEqual(report["summary"]["total_images"], 1)
            self.assertEqual(report["summary"]["missing_images"], 1)
            self.assertEqual(report["items"][0]["status"], "missing-image")

    def test_apply_captions_inserts_caption_below_plain_image(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            vault_root = Path(tmp_dir)
            note_dir = vault_root / "stock" / "调研笔记"
            note_dir.mkdir(parents=True)
            note_path = note_dir / "研报阅读.md"
            image_path = note_dir / "image.png"
            image_path.write_text("image", encoding="utf-8")
            original = "![[image.png]]\n\n----\n"
            note_path.write_text(original, encoding="utf-8")

            caption_images_in_note.apply_captions(
                note_path,
                [{"line_index": 0, "caption": "- 产业链图：说明文字。"}],
            )

            self.assertEqual(
                note_path.read_text(encoding="utf-8"),
                "![[image.png]]\n- 产业链图：说明文字。\n\n----\n",
            )

    def test_apply_captions_preserves_nested_list_indentation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            note_path = Path(tmp_dir) / "nested.md"
            note_path.write_text("1. Topic\n   1. ![[image-7.png]]\n", encoding="utf-8")

            caption_images_in_note.apply_captions(
                note_path,
                [
                    {
                        "line_index": 1,
                        "caption": "- 散热方案对比图：说明文字。",
                        "indent": "   ",
                    }
                ],
            )

            self.assertEqual(
                note_path.read_text(encoding="utf-8"),
                "1. Topic\n   1. ![[image-7.png]]\n   - 散热方案对比图：说明文字。\n",
            )

    def test_default_flow_is_idempotent_after_first_apply(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            vault_root = Path(tmp_dir)
            note_dir = vault_root / "stock" / "调研笔记"
            note_dir.mkdir(parents=True)
            note_path = note_dir / "研报阅读.md"
            image_path = note_dir / "image.png"
            image_path.write_text("image", encoding="utf-8")
            note_path.write_text("![[image.png]]\n\n----\n", encoding="utf-8")

            first_scan = caption_images_in_note.scan_note(note_path, vault_root)
            self.assertEqual(first_scan["summary"]["pending_captions"], 1)
            caption_images_in_note.apply_captions(
                note_path,
                [{"line_index": 0, "caption": "- 图：说明文字。"}],
            )

            second_scan = caption_images_in_note.scan_note(note_path, vault_root)
            self.assertEqual(second_scan["summary"]["pending_captions"], 0)
            self.assertEqual(second_scan["summary"]["already_captioned"], 1)

    def test_run_cli_dry_run_scans_without_modifying_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            vault_root = Path(tmp_dir)
            note_dir = vault_root / "stock" / "调研笔记"
            note_dir.mkdir(parents=True)
            note_path = note_dir / "研报阅读.md"
            (note_dir / "image.png").write_text("image", encoding="utf-8")
            original = "![[image.png]]\n\n----\n"
            note_path.write_text(original, encoding="utf-8")

            result = caption_images_in_note.run_cli(
                [str(note_path), "--vault-root", str(vault_root), "--dry-run"]
            )

            self.assertEqual(result["mode"], "scan")
            self.assertTrue(result["dry_run"])
            self.assertEqual(result["summary"]["pending_captions"], 1)
            self.assertEqual(note_path.read_text(encoding="utf-8"), original)

    def test_force_makes_existing_caption_eligible_for_reapply(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            vault_root = Path(tmp_dir)
            note_dir = vault_root / "stock" / "调研笔记"
            note_dir.mkdir(parents=True)
            note_path = note_dir / "研报阅读.md"
            (note_dir / "image.png").write_text("image", encoding="utf-8")
            note_path.write_text(
                "![[image.png]]\n- 已有说明：旧文字。\n\n----\n",
                encoding="utf-8",
            )

            default_result = caption_images_in_note.run_cli(
                [str(note_path), "--vault-root", str(vault_root)]
            )
            force_result = caption_images_in_note.run_cli(
                [str(note_path), "--vault-root", str(vault_root), "--force"]
            )

            self.assertEqual(default_result["summary"]["already_captioned"], 1)
            self.assertEqual(default_result["summary"]["pending_captions"], 0)
            self.assertEqual(force_result["summary"]["already_captioned"], 0)
            self.assertEqual(force_result["summary"]["pending_captions"], 1)

    def test_run_cli_apply_mode_uses_captions_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            vault_root = Path(tmp_dir)
            note_dir = vault_root / "stock" / "调研笔记"
            note_dir.mkdir(parents=True)
            note_path = note_dir / "研报阅读.md"
            note_path.write_text("![[image.png]]\n\n----\n", encoding="utf-8")
            captions_json = vault_root / "captions.json"
            captions_json.write_text(
                '[{"line_index": 0, "caption": "- 图：说明文字。"}]',
                encoding="utf-8",
            )

            result = caption_images_in_note.run_cli(
                [
                    str(note_path),
                    "--captions-json",
                    str(captions_json),
                    "--vault-root",
                    str(vault_root),
                ]
            )

            self.assertEqual(result["mode"], "apply")
            self.assertEqual(result["summary"]["applied"], 1)
            self.assertEqual(
                note_path.read_text(encoding="utf-8"),
                "![[image.png]]\n- 图：说明文字。\n\n----\n",
            )


if __name__ == "__main__":
    unittest.main()
