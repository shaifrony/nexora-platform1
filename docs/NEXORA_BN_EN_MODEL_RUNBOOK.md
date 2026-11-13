# NEXORA Bengali ↔ English Model Pilot — Runbook

**Status:** prepared; not executed. This is an offline/local inference pilot, not a production translation service.

## 1. Selected checkpoints and access/licensing gates

| Direction | Exact upstream checkpoint | License shown by upstream model card | Access / artifact note |
|---|---|---|---|
| English → Bengali | ai4bharat/indictrans2-en-indic-dist-200M | MIT | Hugging Face gated: user must sign in and accept the model access conditions before downloading. |
| Bengali → English | ai4bharat/indictrans2-indic-en-dist-200M | MIT | Hugging Face gated: user must sign in and accept the model access conditions before downloading. |

Both upstream model cards identify the checkpoints as MIT-licensed. This does not remove the separate access gate: accept the conditions for both model repositories in the user's own Hugging Face account. Do not store access tokens in this repository or paste them into chat.

The checkpoint name says 200M, but the current model repository file listing shows a model.safetensors file around 1.1 GB. Plan for substantial disk and RAM headroom; do not assume the model is a 200 MB download. Record the exact commit SHA for each checkpoint before inference. The runner refuses a moving main reference and requires immutable 40-character revisions.

Argos package index currently lists:
- Bengali → English: translate-bn_en, package version 1.9, Argos version 1.9.0
- English → Bengali: translate-en_bn, package version 1.9, Argos version 1.9.0

The Argos package index does not state a model-artifact license in the relevant metadata rows. Therefore, package availability is confirmed, but commercial redistribution/production-use rights are not verified. Do not select Argos for NEXORA production until the exact downloaded artifact's license/terms are inspected and approved.

## 2. Hardware and environment

- Use a Linux or macOS computer/server, not the user's Android phone for this first pilot.
- IndicTransToolkit documents Python 3.10+ and recommends recent NumPy, PyTorch and Transformers versions. The official IndicTrans2 example uses PyTorch + Hugging Face Transformers + IndicTransToolkit.
- Start with CPU inference only on a machine with adequate free RAM and disk. GPU is optional; do not rent or activate paid compute without explicit budget approval.
- Keep at least several GB of free disk beyond the checkpoint downloads and Python environment. Measure actual peak RAM, runtime and latency; do not infer production sizing from parameter count alone.

## 3. Create a clean environment

Run from the repository root on a Linux/macOS machine:

```bash
python3 --version
python3 -m venv .venv-bn-en
source .venv-bn-en/bin/activate
python -m pip install --upgrade pip
python -m pip install "numpy>=2.1" "torch>=2.5" "transformers>=4.51,<5" accelerate sentencepiece sacremoses argostranslate indictranstoolkit huggingface_hub
```

These are compatibility floors/ranges based on the toolkit's published requirements, not a claim that this exact dependency combination has been tested by NEXORA. Save the resolved package versions (python -m pip freeze) with the results.

## 4. Accept and pin the gated IndicTrans2 models

1. Sign in to Hugging Face in a browser.
2. Open both model cards and accept their access conditions:
   - https://huggingface.co/ai4bharat/indictrans2-en-indic-dist-200M
   - https://huggingface.co/ai4bharat/indictrans2-indic-en-dist-200M
3. Authenticate locally using the Hugging Face CLI. The token remains on the test machine:

```bash
hf auth login
```

4. Resolve and record the immutable commit SHA for each checkpoint:

```bash
python - <<'PY'
from huggingface_hub import HfApi
api = HfApi()
for model in [
    "ai4bharat/indictrans2-en-indic-dist-200M",
    "ai4bharat/indictrans2-indic-en-dist-200M",
]:
    info = api.model_info(model)
    print(model, info.sha)
PY
```

5. Set the returned 40-character SHAs in the environment (do not put tokens or SHAs in public chat):

```bash
export HF_REVISION_EN_BN="PASTE_EN_TO_BN_COMMIT_SHA"
export HF_REVISION_BN_EN="PASTE_BN_TO_EN_COMMIT_SHA"
```

If either model access is denied, stop and resolve the access gate. Do not use unofficial mirrors as a shortcut.

## 5. Run the pilot

The script reads the 24 parallel examples from docs/NEXORA_BN_EN_PILOT_CORPUS.md. It records raw outputs and per-case latency to a CSV. It does not compute an automatic quality winner.

```bash
python scripts/translation_pilot/run_bn_en_pilot.py --backend both --direction both
```

Or isolate one candidate/direction:

```bash
python scripts/translation_pilot/run_bn_en_pilot.py --backend argos --direction both
python scripts/translation_pilot/run_bn_en_pilot.py --backend indictrans2 --direction bn-en
```

Expected output path: artifacts/translation-pilot/bn-en-results-<UTC timestamp>.csv.

The first Argos run downloads and installs the exact indexed 1.9 packages. The first IndicTrans2 run downloads the two gated model checkpoints. This can consume multiple GB and take time. Do not run on a metered/paid connection or paid compute without approval.

## 6. Human review and decision

- First, two independent bilingual reviewers must validate the seed references in NEXORA_BN_EN_PILOT_CORPUS.md. The references are not ground truth until reviewed.
- Keep model outputs unchanged. Reviewers score meaning preservation, fluency, omissions/additions and protected-token accuracy separately.
- Treat any changed negation, price, quantity, currency, date, unit, product/order ID or delivery instruction as a critical error.
- Record exact model revision, Argos package version, Python/package versions, hardware, peak RAM/VRAM, cold-start, per-case latency and throughput.
- 24 examples per direction is only a screening pilot. Expand the corpus before making a production decision. Optional chrF++/COMET scores require validated references and must not replace human review.

## 7. Privacy and deployment boundary

- Use only the synthetic corpus in this repository. Never export Buyer/Seller/Porter/Admin private conversations into this pilot.
- No public translation demo/API is used. Model inference is local to the machine running this script.
- No NEXORA Edge Function, provider key, translation API, SQL migration, Supabase setting or production integration is created by this runbook.
- Automatic translation remains disabled. Any future live translation must be a consent-based, authenticated server-side feature with participant authorization, privacy-safe logging, rate limits, cache controls and original-text access.

## 8. Current limitations

- Neither model has been executed by NEXORA in this environment.
- IndicTrans2 license is identified as MIT by the upstream model cards, but Hugging Face access is gated and must be accepted by the operator.
- Argos package versions are confirmed; exact model artifact license/terms remain unverified.
- The runner has been added to source but has not been executed against downloaded model dependencies. Treat it as an initial runner requiring a first controlled dry run on a suitable computer.