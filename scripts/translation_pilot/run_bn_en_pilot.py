#!/usr/bin/env python3
"""Run the NEXORA synthetic Bengali-English pilot corpus against local models.

No network translation API is used. Model downloads occur only when the user
explicitly runs this script and chooses a backend. Never put private chat data
in the corpus or results.
"""
from __future__ import annotations

import argparse
import csv
import os
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "docs" / "NEXORA_BN_EN_PILOT_CORPUS.md"

MODEL_IDS = {
    "en_bn": "ai4bharat/indictrans2-en-indic-dist-200M",
    "bn_en": "ai4bharat/indictrans2-indic-en-dist-200M",
}


def load_corpus():
    rows = []
    for line in CORPUS.read_text(encoding="utf-8").splitlines():
        if not re.match(r"^\| T\d{2} \|", line):
            continue
        cells = [part.strip() for part in line.strip().strip("|").split("|")]
        if len(cells) != 4:
            raise ValueError(f"Malformed corpus row: {line}")
        case_id, coverage, bn_text, en_text = cells
        rows.append({"id": case_id, "coverage": coverage, "bn": bn_text, "en": en_text})
    if len(rows) != 24:
        raise RuntimeError(f"Expected 24 corpus cases, found {len(rows)}")
    return rows


def run_argos(rows, directions):
    try:
        import argostranslate.package as package
        import argostranslate.translate as translate
    except ImportError as exc:
        raise RuntimeError("Install Argos first: pip install argostranslate") from exc

    package.update_package_index()
    available = package.get_available_packages()
    wanted = {
        "bn_en": ("bn", "en"),
        "en_bn": ("en", "bn"),
    }
    for direction in directions:
        src, tgt = wanted[direction]
        matches = [
            item for item in available
            if item.from_code == src
            and item.to_code == tgt
            and str(item.package_version) == "1.9"
            and str(item.argos_version) == "1.9.0"
        ]
        if len(matches) != 1:
            raise RuntimeError(
                f"Expected exactly one Argos {src}->{tgt} package v1.9 "
                f"(Argos 1.9.0); found {len(matches)}"
            )
        installed = package.get_installed_packages()
        already = any(
            item.from_code == src and item.to_code == tgt
            and str(item.package_version) == "1.9"
            for item in installed
        )
        if not already:
            download_path = matches[0].download()
            package.install_from_path(download_path)

    installed_languages = translate.get_installed_languages()
    by_code = {lang.code: lang for lang in installed_languages}
    output = []
    for direction in directions:
        src, tgt = wanted[direction]
        if src not in by_code or tgt not in by_code:
            raise RuntimeError(f"Argos languages not installed: {src}, {tgt}")
        translator = by_code[src].get_translation(by_code[tgt])
        for row in rows:
            source = row["bn"] if direction == "bn_en" else row["en"]
            reference = row["en"] if direction == "bn_en" else row["bn"]
            started = time.perf_counter()
            translated = translator.translate(source)
            elapsed = (time.perf_counter() - started) * 1000
            output.append({
                "candidate": "Argos",
                "model_id": f"translate-{src}_{tgt} package 1.9 / Argos 1.9.0",
                "revision": "package index version pin; artifact hash recorded separately if desired",
                "direction": direction,
                "case_id": row["id"],
                "coverage": row["coverage"],
                "source": source,
                "reference": reference,
                "output": translated,
                "latency_ms": f"{elapsed:.2f}",
            })
    return output


def run_indictrans2(rows, directions):
    try:
        import torch
        from transformers import AutoModelForSeq2SeqLM, AutoTokenizer
        from IndicTransToolkit import IndicProcessor
    except ImportError as exc:
        raise RuntimeError(
            "IndicTrans2 dependencies missing. See docs/NEXORA_BN_EN_MODEL_RUNBOOK.md"
        ) from exc

    device = "cuda" if torch.cuda.is_available() else "cpu"
    processor = IndicProcessor(inference=True)
    output = []
    lang_codes = {"bn_en": ("ben_Beng", "eng_Latn"), "en_bn": ("eng_Latn", "ben_Beng")}

    for direction in directions:
        revision_env = "HF_REVISION_BN_EN" if direction == "bn_en" else "HF_REVISION_EN_BN"
        revision = os.environ.get(revision_env, "").strip()
        if not re.fullmatch(r"[0-9a-f]{40}", revision):
            raise RuntimeError(
                f"Set {revision_env} to the exact 40-character Hugging Face commit SHA "
                "after accepting the gated model conditions. Do not use a moving main branch."
            )
        model_id = MODEL_IDS[direction]
        src_lang, tgt_lang = lang_codes[direction]
        tokenizer = AutoTokenizer.from_pretrained(
            model_id, revision=revision, trust_remote_code=True
        )
        model = AutoModelForSeq2SeqLM.from_pretrained(
            model_id, revision=revision, trust_remote_code=True,
            low_cpu_mem_usage=True
        ).to(device)
        model.eval()

        for row in rows:
            source = row["bn"] if direction == "bn_en" else row["en"]
            reference = row["en"] if direction == "bn_en" else row["bn"]
            started = time.perf_counter()
            batch = processor.preprocess_batch(
                [source], src_lang=src_lang, tgt_lang=tgt_lang, visualize=False
            )
            inputs = tokenizer(
                batch, padding="longest", truncation=True, max_length=256,
                return_tensors="pt"
            ).to(device)
            with torch.inference_mode():
                generated = model.generate(
                    **inputs, num_beams=5, num_return_sequences=1, max_length=256
                )
            decoded = tokenizer.batch_decode(
                generated, skip_special_tokens=True,
                clean_up_tokenization_spaces=True
            )
            translated = processor.postprocess_batch(decoded, lang=tgt_lang)[0]
            elapsed = (time.perf_counter() - started) * 1000
            output.append({
                "candidate": "IndicTrans2",
                "model_id": model_id,
                "revision": revision,
                "direction": direction,
                "case_id": row["id"],
                "coverage": row["coverage"],
                "source": source,
                "reference": reference,
                "output": translated,
                "latency_ms": f"{elapsed:.2f}",
            })
        del model, tokenizer
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend", choices=("argos", "indictrans2", "both"), default="both")
    parser.add_argument("--direction", choices=("both", "bn-en", "en-bn"), default="both")
    parser.add_argument("--output", default="", help="CSV output path; default creates a UTC timestamped file")
    args = parser.parse_args()

    directions = ["bn_en", "en_bn"] if args.direction == "both" else [
        "bn_en" if args.direction == "bn-en" else "en_bn"
    ]
    rows = load_corpus()
    results = []

    backends = ["argos", "indictrans2"] if args.backend == "both" else [args.backend]
    for backend in backends:
        print(f"Running {backend} for {', '.join(directions)}", flush=True)
        try:
            if backend == "argos":
                results.extend(run_argos(rows, directions))
            else:
                results.extend(run_indictrans2(rows, directions))
        except Exception as exc:
            print(f"ERROR [{backend}]: {exc}", file=sys.stderr)
            if args.backend != "both":
                raise
            print("Continuing to the next backend; no result rows were fabricated.", file=sys.stderr)

    if not results:
        raise SystemExit("No model results produced. Check dependencies, access and revisions.")

    output_path = Path(args.output) if args.output else (
        ROOT / "artifacts" / "translation-pilot" /
        f"bn-en-results-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.csv"
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "candidate", "model_id", "revision", "direction", "case_id",
        "coverage", "source", "reference", "output", "latency_ms"
    ]
    with output_path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(results)
    print(f"Wrote {len(results)} raw outputs to {output_path}")
    print("Human review is still required. No automatic winner/quality score is calculated.")


if __name__ == "__main__":
    main()
