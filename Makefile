# ============================================================
# BitNet.cpp — Docker Makefile
# ============================================================
# Usage:
#   make build                       Build using cached base image (no network needed)
#   make build-pull                  Build pulling fresh base layers from Docker Hub
#   make setup MODEL=<hf-repo>       Download model & compile kernels
#   make run PROMPT="Hello"          Run interactive inference
#   make chat PROMPT="sys prompt"    Run in conversation/chat mode
#   make benchmark                   Run e2e benchmark
#   make shell                       Open a bash shell in the container
#   make download MODEL=<hf-repo>    Download a model from Hugging Face
#   make logs                        Print cmake compile log (debug setup failures)
#   make clean                       Remove containers
#   make clean-build                 Remove build-artifact volume (force recompile)
#   make clean-image                 Remove the built Docker image
# ============================================================

COMPOSE         := docker compose
IMAGE           := bitnet-cpp:latest

# Default model (HF repo ID and local directory name)
MODEL           ?= microsoft/BitNet-b1.58-2B-4T-gguf
MODEL_DIR       ?= models/BitNet-b1.58-2B-4T
QUANT_TYPE      ?= i2_s
THREADS         ?= 4
N_TOKEN         ?= 128
N_PROMPT        ?= 512
CTX_SIZE        ?= 2048
TEMPERATURE     ?= 0.8
PROMPT          ?= You are a helpful assistant.
GGUF_PATH       ?= $(MODEL_DIR)/ggml-model-$(QUANT_TYPE).gguf

.PHONY: all build build-pull setup download run chat benchmark shell logs clean clean-build clean-image help

all: setup

## Build the Docker image (uses locally cached base layers; no Docker Hub access needed)
## Disables BuildKit so Docker uses the legacy builder, which skips registry
## manifest checks when the base image is already present in the local cache.
build: export DOCKER_BUILDKIT := 0
build:
	$(COMPOSE) build

## Build the Docker image, pulling fresh base layers from Docker Hub
build-pull:
	$(COMPOSE) build --pull

## Download a model from Hugging Face into ./models, then compile kernels.
## Override MODEL and MODEL_DIR to use a different repo:
##   make setup MODEL=1bitLLM/bitnet_b1_58-large MODEL_DIR=models/bitnet_b1_58-large
setup: build
	$(COMPOSE) run --rm \
		-e HUGGING_FACE_HUB_TOKEN=$(HF_TOKEN) \
		bitnet bash -c "\
		  huggingface-cli download $(MODEL) --local-dir $(MODEL_DIR) && \
		  python3 setup_env.py -md $(MODEL_DIR) -q $(QUANT_TYPE)"

## Download only (no kernel compilation)
download: build
	$(COMPOSE) run --rm \
		-e HUGGING_FACE_HUB_TOKEN=$(HF_TOKEN) \
		bitnet bash -c "\
		  huggingface-cli download $(MODEL) --local-dir $(MODEL_DIR)"

## Run a single inference pass
##   make run PROMPT="Tell me a joke" GGUF_PATH=models/.../ggml-model-i2_s.gguf
run: build
	$(COMPOSE) run --rm bitnet \
		python3 run_inference.py \
		  -m $(GGUF_PATH) \
		  -p "$(PROMPT)" \
		  -t $(THREADS) \
		  -c $(CTX_SIZE) \
		  -temp $(TEMPERATURE)

## Run in conversation / chat mode (system prompt via -p)
##   make chat PROMPT="You are a pirate assistant."
chat: build
	$(COMPOSE) run --rm bitnet \
		python3 run_inference.py \
		  -m $(GGUF_PATH) \
		  -p "$(PROMPT)" \
		  -t $(THREADS) \
		  -c $(CTX_SIZE) \
		  -temp $(TEMPERATURE) \
		  -cnv

## Run the end-to-end benchmark
benchmark: build
	$(COMPOSE) run --rm \
		-e MODEL_PATH=$(GGUF_PATH) \
		-e N_TOKEN=$(N_TOKEN) \
		-e N_PROMPT=$(N_PROMPT) \
		-e BITNET_THREADS=$(THREADS) \
		--profile benchmark \
		benchmark

## Open an interactive bash shell inside the container
shell: build
	$(COMPOSE) run --rm --entrypoint bash bitnet

## Convert a .safetensors checkpoint to GGUF format
##   make convert SRC_DIR=models/bitnet-b1.58-2B-4T-bf16
convert: build
ifndef SRC_DIR
	$(error SRC_DIR is required. Usage: make convert SRC_DIR=models/my-bf16-model)
endif
	$(COMPOSE) run --rm bitnet \
		python3 utils/convert-helper-bitnet.py $(SRC_DIR)

## Generate a dummy model for benchmarking (no real weights needed)
##   make dummy-model SIZE=125M OUTTYPE=tl1
dummy-model: build
	$(COMPOSE) run --rm bitnet \
		python3 utils/generate-dummy-bitnet-model.py models/bitnet_b1_58-large \
		  --outfile models/dummy-bitnet-$(SIZE).$(OUTTYPE).gguf \
		  --outtype $(OUTTYPE) \
		  --model-size $(SIZE)

## Print the cmake compile log from the last setup run (useful when setup fails)
logs:
	$(COMPOSE) run --rm bitnet sh -c "cat logs/compile.log 2>/dev/null || echo 'No compile.log found — run make setup first'"

## Stop and remove containers; keep model volume
clean:
	$(COMPOSE) down --remove-orphans

## Remove the build-artifact volume (forces cmake re-compile on next setup)
clean-build:
	docker volume rm $$(docker volume ls -q --filter name=bitnet-build) 2>/dev/null || true

## Remove the built image (forces full rebuild on next `make build`)
clean-image: clean
	docker rmi $(IMAGE) 2>/dev/null || true

## Show this help
help:
	@echo ""
	@echo "  BitNet.cpp Docker Makefile"
	@echo ""
	@echo "  Targets:"
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /    /'
	@echo ""
	@echo "  Key variables (override on the command line):"
	@echo "    MODEL        HF repo to download  (default: $(MODEL))"
	@echo "    MODEL_DIR    Local model directory (default: $(MODEL_DIR))"
	@echo "    QUANT_TYPE   Quantization type     (default: $(QUANT_TYPE))"
	@echo "    GGUF_PATH    Path to .gguf file    (default: $(GGUF_PATH))"
	@echo "    THREADS      CPU thread count      (default: $(THREADS))"
	@echo "    PROMPT       Inference prompt      (default: '$(PROMPT)')"
	@echo "    HF_TOKEN     Hugging Face token    (for gated models)"
	@echo ""
