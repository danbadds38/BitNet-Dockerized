# BitNet.cpp — Docker Setup

Dockerized environment for [microsoft/BitNet](https://github.com/microsoft/BitNet), the official inference framework for 1-bit LLMs.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) with Docker Compose v2
- `make`
- A Hugging Face account (and token for gated models)

## Quick Start

```bash
# 1. Copy and fill in environment variables
cp .env.example .env
# Edit .env — set HF_TOKEN if you have one

# 2. Build the image
make build

# 3. Download the default model (BitNet-b1.58-2B-4T) and compile kernels
make setup

# 4. Run inference
make run PROMPT="Tell me a joke"

# 5. Run in interactive chat mode
make chat PROMPT="You are a helpful assistant."
```

## Project Structure

```
.
├── Dockerfile            # Ubuntu 22.04 + Clang 18 + CMake 3.22+
├── docker-compose.yml    # Service definitions
├── Makefile              # Developer workflow shortcuts
├── .dockerignore         # Keeps the build context fast (excludes models/)
├── .env.example          # Environment variable template
└── models/               # Downloaded model files (git-ignored, volume-mounted)
```

## Environment Variables

Copy `.env.example` to `.env` before running:

| Variable | Default | Description |
|---|---|---|
| `HF_TOKEN` | _(empty)_ | Hugging Face token for gated models |
| `BITNET_THREADS` | `4` | CPU thread count for inference |
| `MODEL_PATH` | `models/BitNet-b1.58-2B-4T/ggml-model-i2_s.gguf` | Path to `.gguf` inside container |
| `N_TOKEN` | `128` | Tokens to generate (benchmark) |
| `N_PROMPT` | `512` | Prompt tokens (benchmark) |

## Makefile Reference

| Target | Description |
|---|---|
| `make build` | Build the Docker image |
| `make setup` | Download default model + compile kernels |
| `make run PROMPT="..."` | Single inference pass |
| `make chat PROMPT="..."` | Interactive conversation mode (`-cnv`) |
| `make benchmark` | Run `e2e_benchmark.py` |
| `make shell` | Open a bash shell inside the container |
| `make download MODEL=<repo>` | Download a model without compiling |
| `make convert SRC_DIR=<dir>` | Convert `.safetensors` → GGUF |
| `make dummy-model SIZE=125M OUTTYPE=tl1` | Generate a dummy model for benchmarking |
| `make clean` | Remove containers and build volume |
| `make clean-image` | Remove the Docker image |

### Overridable Variables

All variables can be set on the command line:

```bash
make setup \
  MODEL=1bitLLM/bitnet_b1_58-large \
  MODEL_DIR=models/bitnet_b1_58-large \
  QUANT_TYPE=tl1

make run \
  GGUF_PATH=models/bitnet_b1_58-large/ggml-model-tl1.gguf \
  PROMPT="Explain quantum computing" \
  THREADS=8 \
  CTX_SIZE=4096 \
  TEMPERATURE=0.7
```

## Supported Models

| Model | Parameters | HF Repo |
|---|---|---|
| BitNet-b1.58-2B-4T *(default)* | 2.4B | `microsoft/BitNet-b1.58-2B-4T-gguf` |
| bitnet_b1_58-large | 0.7B | `1bitLLM/bitnet_b1_58-large` |
| bitnet_b1_58-3B | 3.3B | `1bitLLM/bitnet_b1_58-3B` |
| Llama3-8B-1.58-100B | 8.0B | `HF1BitLLM/Llama3-8B-1.58-100B-tokens` |
| Falcon3 (various) | 1B–10B | `tiiuae/Falcon3-*-Instruct-1.58bit` |

## Examples

```bash
# Use a different model
make setup MODEL=1bitLLM/bitnet_b1_58-large \
           MODEL_DIR=models/bitnet_b1_58-large \
           QUANT_TYPE=tl1

# Benchmark with custom params
make benchmark GGUF_PATH=models/bitnet_b1_58-large/ggml-model-tl1.gguf \
               N_TOKEN=200 N_PROMPT=256 THREADS=8

# Convert a bf16 safetensors checkpoint to GGUF
make download MODEL=microsoft/bitnet-b1.58-2B-4T-bf16 \
              MODEL_DIR=models/bitnet-b1.58-2B-4T-bf16
make convert SRC_DIR=models/bitnet-b1.58-2B-4T-bf16

# Generate a dummy model and benchmark (no download needed)
make dummy-model SIZE=125M OUTTYPE=tl1
make benchmark GGUF_PATH=models/dummy-bitnet-125M.tl1.gguf
```

## Notes

- **Model storage**: models are stored in `./models/` on your host and bind-mounted into the container. They are never baked into the image.
- **Build cache**: compiled kernel binaries are stored in the `bitnet-build` Docker named volume, so `make run` after the first `make setup` is fast.
- **GPU support**: the current Dockerfile targets CPU inference. GPU support can be added by switching to a CUDA base image and passing `-DGGML_CUDA=ON` to CMake in `setup_env.py`.
