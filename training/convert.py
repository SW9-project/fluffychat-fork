"""Step 7: converts the fine-tuned model to the .litertlm file the app runs.

    training/.convert-venv/bin/python training/convert.py

Needs its own environment, because litert-torch pins an older PyTorch than
train.py uses:

    uv venv training/.convert-venv --python 3.12
    VIRTUAL_ENV=training/.convert-venv uv pip install litert-torch

and the base model file for its LLM metadata (`bash
scripts/fetch_personalization_model.sh --baseline`). See TRAINING.md, step 7.

What is copied from the base file and what changes:

- The LLM metadata (start token, stop tokens, `function_gemma` model type) is
  the base file's, so LiteRT-LM formats the prompt with the same native
  FunctionGemma formatter the app already used. Only `max_num_tokens` changes.
- The KV cache is 2048 instead of 1024: the eleven declarations alone are ~1300
  tokens, and a conversation adds up to ~200 more plus the answer.
- Prefill in chunks of 256 and a transposed KV cache with the mask as input,
  like the base file. dynamic_int8 quantization, like the base file.
"""

import argparse
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent
REPO = ROOT.parent

DEFAULT_CHECKPOINT = ROOT / "output" / "functiongemma-pilot"
DEFAULT_BASE = REPO / "assets/models/baseline/functiongemma-270M-it.litertlm"
DEFAULT_NAME = "functiongemma-270M-sw9-tools1"
DEFAULT_OUT = REPO / "assets/models"

KV_CACHE = 2048
PREFILL = 256


def dump_base(base: pathlib.Path, dump: pathlib.Path) -> None:
    """Unpacks the base file: its model.toml, LlmMetadata and tokenizer."""
    subprocess.run(
        [
            sys.executable,
            "-m",
            "litert_lm_builder.litertlm_peek_main",
            "--litertlm_file",
            str(base),
            "--dump_files_dir",
            str(dump),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    from google.protobuf import text_format
    from litert_lm_builder.runtime.proto import llm_metadata_pb2

    path = dump / "LlmMetadataProto.pbtext"
    metadata = llm_metadata_pb2.LlmMetadata()
    text_format.Parse(path.read_text(), metadata)
    if metadata.llm_model_type.WhichOneof("model_type") != "function_gemma":
        sys.exit(f"{base} is not a FunctionGemma file")
    metadata.max_num_tokens = KV_CACHE
    path.write_text(text_format.MessageToString(metadata))
    print(text_format.MessageToString(metadata))


def export_tflite(checkpoint: pathlib.Path, workdir: pathlib.Path, name: str) -> pathlib.Path:
    """The fine-tuned model as one TFLite file with prefill and decode
    signatures. Kept in workdir, so packing again does not convert again."""
    existing = sorted(workdir.glob(f"{name}*.tflite"))
    if existing:
        print(f"Using {existing[-1]}")
        return existing[-1]

    without_tensorflow()
    from litert_torch.generative.examples.gemma3 import gemma3
    from litert_torch.generative.layers import kv_cache
    from litert_torch.generative.utilities import converter
    from litert_torch.generative.utilities.export_config import ExportConfig

    model = gemma3.build_model_270m(str(checkpoint))
    converter.convert_to_tflite(
        model,
        output_path=str(workdir),
        output_name_prefix=name,
        prefill_seq_len=PREFILL,
        kv_cache_max_len=KV_CACHE,
        quantize="dynamic_int8",
        export_config=ExportConfig(
            kvcache_layout=kv_cache.KV_LAYOUT_TRANSPOSED,
            mask_as_input=True,
        ),
    )
    built = sorted(workdir.glob(f"{name}*.tflite"))
    if len(built) != 1:
        sys.exit(f"Expected one .tflite, found {built}")
    return built[0]


def without_tensorflow() -> None:
    """litert-torch's LoRA layer imports one module from TensorFlow, its TFLite
    flatbuffer schema, and nothing on this path uses it. Installing TensorFlow
    next to litert-converter crashes on import (both register the same LLVM
    options), so the import gets LiteRT's own copy of the schema instead."""
    import importlib.machinery
    import importlib.util
    import types

    if importlib.util.find_spec("tensorflow") is not None:
        return
    from ai_edge_litert import schema_py_generated

    for name in ("tensorflow", "tensorflow.lite", "tensorflow.lite.python"):
        module = types.ModuleType(name)
        module.__path__ = []
        # PyTorch's tracer asks every loaded module for its spec.
        module.__spec__ = importlib.machinery.ModuleSpec(name, None, is_package=True)
        sys.modules[name] = module
    sys.modules["tensorflow.lite.python.schema_py_generated"] = schema_py_generated
    sys.modules["tensorflow.lite.python"].schema_py_generated = schema_py_generated


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--checkpoint", type=pathlib.Path, default=DEFAULT_CHECKPOINT)
    parser.add_argument("--base", type=pathlib.Path, default=DEFAULT_BASE)
    parser.add_argument("--name", default=DEFAULT_NAME)
    parser.add_argument("--out", type=pathlib.Path, default=DEFAULT_OUT)
    parser.add_argument("--workdir", type=pathlib.Path, default=ROOT / "output" / "convert")
    args = parser.parse_args()

    for path in (args.checkpoint / "model.safetensors", args.base):
        if not path.exists():
            sys.exit(f"Missing {path}")
    args.workdir.mkdir(parents=True, exist_ok=True)
    tflite = export_tflite(args.checkpoint, args.workdir, args.name)

    from litert_lm_builder import litertlm_builder

    with tempfile.TemporaryDirectory() as tmp:
        dump = pathlib.Path(tmp)
        dump_base(args.base, dump)
        # The base file's sections, with the fine-tuned model in place of its
        # own: same metadata (but the context length), same tokenizer.
        toml = dump / "model.toml"
        old = next(dump.glob("*_TFLiteModel_*.tflite")).name
        toml.write_text(toml.read_text().replace(old, str(tflite)))
        args.out.mkdir(parents=True, exist_ok=True)
        target = args.out / f"{args.name}.litertlm"
        litertlm_builder.pack(str(toml), str(target))
    print(f"Saved {target}")


if __name__ == "__main__":
    main()
