# BitNet.cpp — Docker Setup

Dockerized environment for [microsoft/BitNet](https://github.com/microsoft/BitNet), the official inference framework for 1-bit LLMs (BitNet b1.58). Runs entirely on CPU — no GPU required.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) with Docker Compose v2
- `make`
- A [Hugging Face account](https://huggingface.co/join) (token required only for gated/private models)

---

## Quick Start

```bash
# 1. Configure your environment
cp .env.example .env
# Edit .env — set HF_TOKEN if needed, tune threads/context to taste

# 2. Build the Docker image
make build

# 3. Download the default 2.4B model and compile BitNet kernels
make setup

# 4. Run a single inference
make run PROMPT="Explain quantum computing in simple terms"

# 5. Or start an interactive chat session
make chat PROMPT="You are a helpful assistant."
```

---

## Project Structure

```
.
├── Dockerfile            # Ubuntu 22.04 + Clang 18 + CMake 3.22+
├── docker-compose.yml    # Service and volume definitions
├── Makefile              # All developer workflow targets
├── .env                  # Your local config (git-ignored)
├── .env.example          # Config template — copy to .env
├── .dockerignore         # Excludes models/ and logs/ from build context
└── models/               # Downloaded model files (host bind-mount, git-ignored)
```

---

## Configuration (`.env`)

Copy `.env.example` to `.env`. Both `docker compose` and the `Makefile` read it automatically. Command-line overrides (`make VAR=value`) always take highest precedence.

| Variable | Default | Description |
|---|---|---|
| `HF_TOKEN` | _(empty)_ | Hugging Face token — required for gated/private models |
| `MODEL` | `microsoft/BitNet-b1.58-2B-4T-gguf` | HF repo to download |
| `MODEL_DIR` | `models/BitNet-b1.58-2B-4T` | Local directory for model files |
| `QUANT_TYPE` | `i2_s` | Quantization type (`i2_s` or `tl1`) |
| `THREADS` | `4` | CPU threads for inference — set to your physical core count |
| `CTX_SIZE` | `2048` | Context window size in tokens (max 4096 for the 2B model) |
| `N_TOKEN` | `128` | Maximum tokens to generate per response |
| `TEMPERATURE` | `0.8` | Sampling temperature (higher = more creative) |
| `N_PROMPT` | `512` | Prompt tokens used in benchmarks |

---

## Makefile Reference

### Building

| Target | Description |
|---|---|
| `make build` | Build image using locally cached base layers (no internet needed) |
| `make build-pull` | Build image, pulling fresh base layers from Docker Hub |

### Model Setup

One-time step per model — downloads weights and compiles BitNet kernels.

| Target | Size | Model |
|---|---|---|
| `make setup` | **2.4B** *(default)* | `microsoft/BitNet-b1.58-2B-4T-gguf` |
| `make setup-small` | 0.7B | `1bitLLM/bitnet_b1_58-large` |
| `make setup-3b` | 3.3B | `1bitLLM/bitnet_b1_58-3B` |
| `make setup-llama` | 8.0B | `HF1BitLLM/Llama3-8B-1.58-100B-tokens` |
| `make setup-falcon1b` | 1B | `tiiuae/Falcon3-1B-Instruct-1.58bit` |
| `make setup-falcon3b` | 3B | `tiiuae/Falcon3-3B-Instruct-1.58bit` |
| `make setup-falcon7b` | 7B | `tiiuae/Falcon3-7B-Instruct-1.58bit` |
| `make setup-falcon10b` | 10B | `tiiuae/Falcon3-10B-Instruct-1.58bit` |

You can also use a custom model directly:

```bash
make setup MODEL=1bitLLM/bitnet_b1_58-large MODEL_DIR=models/bitnet_b1_58-large
```

### Inference

| Target | Description |
|---|---|
| `make run PROMPT="..."` | Single-shot inference (no chat history) |
| `make chat PROMPT="..."` | Interactive conversation mode — prompt becomes the system prompt |

Key variables for inference:

```bash
make run \
  PROMPT="Write a haiku about Docker" \
  THREADS=8 \
  CTX_SIZE=4096 \
  N_TOKEN=256 \
  TEMPERATURE=0.7
```

To run a model other than the default, pass `GGUF_PATH`:

```bash
make run \
  GGUF_PATH=models/Llama3-8B/ggml-model-i2_s.gguf \
  PROMPT="What is 1-bit quantization?"
```

### Utilities

| Target | Description |
|---|---|
| `make download MODEL=<repo>` | Download model weights only (no kernel compile) |
| `make benchmark` | Run `e2e_benchmark.py` with current model |
| `make convert SRC_DIR=<dir>` | Convert `.safetensors` checkpoint → GGUF |
| `make dummy-model SIZE=125M OUTTYPE=tl1` | Generate dummy weights for benchmarking |
| `make shell` | Open an interactive bash shell inside the container |
| `make logs` | Print the cmake compile log (useful when `setup` fails) |

### Cleanup

| Target | Description |
|---|---|
| `make clean` | Stop and remove containers (keeps models and build cache) |
| `make clean-build` | Remove the build-artifact volume (forces kernel recompile) |
| `make clean-image` | Remove the Docker image (forces full rebuild) |

---

## Examples

```bash
# Chat with the fast 0.7B model
make setup-small
make chat GGUF_PATH=models/bitnet_b1_58-large/ggml-model-i2_s.gguf \
          PROMPT="You are a concise coding assistant."

# Benchmark the 8B Llama model on 8 threads
make setup-llama
make benchmark \
  GGUF_PATH=models/Llama3-8B/ggml-model-i2_s.gguf \
  N_TOKEN=200 N_PROMPT=256 THREADS=8

# Convert a bf16 safetensors checkpoint to GGUF and run it
make download MODEL=microsoft/bitnet-b1.58-2B-4T-bf16 \
              MODEL_DIR=models/bitnet-b1.58-2B-4T-bf16
make convert  SRC_DIR=models/bitnet-b1.58-2B-4T-bf16
make run      GGUF_PATH=models/bitnet-b1.58-2B-4T-bf16/ggml-model-i2_s.gguf \
              PROMPT="Hello"

# Generate a dummy model and benchmark without downloading anything
make dummy-model SIZE=125M OUTTYPE=tl1
make benchmark GGUF_PATH=models/dummy-bitnet-125M.tl1.gguf
```

---

## Notes

- **Model storage** — weights live in `./models/` on your host and are bind-mounted into the container. They are never baked into the image and survive `make clean`.
- **Build cache** — compiled kernel binaries are stored in the `bitnet-build` Docker named volume. `make run` after the first `make setup` is instant. Use `make clean-build` to force a recompile.
- **Context limit** — the 2B model supports a maximum of 4096 tokens (`CTX_SIZE=4096`). Larger models may support more.
- **GPU support** — the current Dockerfile targets CPU-only inference. GPU support can be added by switching to a CUDA base image and passing `-DGGML_CUDA=ON` to CMake inside `setup_env.py`.
- **Offline builds** — `make build` uses the legacy Docker builder (`DOCKER_BUILDKIT=0`), which skips the Docker Hub registry manifest check when `ubuntu:22.04` is already in your local cache. Use `make build-pull` when you want to refresh the base image.
