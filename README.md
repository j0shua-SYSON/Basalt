# Basalt

Basalt is a private, on-device AI chat app for iPhone and iPad. It imports local
GGUF files or downloads a GGUF from Hugging Face, then runs inference entirely
on the device with Metal-accelerated [llama.cpp](https://github.com/ggml-org/llama.cpp).
No model, prompt, or response is sent to a Basalt service.

> Basalt is early open-source software. Start with a small 1B-3B parameter,
> 4-bit GGUF that fits comfortably in your device's memory.

## Highlights

- Local `.gguf` import through the system document picker
- Hugging Face `blob`, `resolve`, and direct GGUF URL imports
- Streaming token generation with cancel, copy, retry, and performance metrics
- Capability-aware thinking controls with separately rendered reasoning
- Image and audio prompts through a matching llama.cpp multimodal projector
- Opt-in Brave Search or SearXNG grounding with visible source cards
- Sampling presets plus context, sampler, CPU, GPU, memory, and stop controls
- Adaptive SwiftUI navigation for compact iPhone and spacious iPad layouts
- Model library with storage usage, source provenance, and safe deletion
- No analytics, accounts, ads, or bundled model

## Build

Requirements: macOS, Xcode 16.4 or newer, and iOS/iPadOS 17 or newer.

```bash
git clone https://github.com/j0shua-SYSON/Basalt.git
cd Basalt
./Scripts/bootstrap.sh
open Basalt.xcodeproj
```

`bootstrap.sh` downloads pinned copies of XcodeGen and the official llama.cpp
XCFramework into this repository. It does not install global tools. Generated
projects, dependencies, DerivedData, test results, and captures are ignored by
Git.

To build without code signing:

```bash
./Scripts/build.sh
```

## Importing models

In **Models**, choose **Add model**. Pick a GGUF already in Files, or paste a
Hugging Face URL such as:

```text
https://huggingface.co/owner/repository/blob/main/model-q4_k_m.gguf
```

Basalt converts Hugging Face `blob` links to download links. Gated repositories
can use a Hugging Face access token for that import; Basalt does not persist the
token. Split GGUF model sets are not yet supported.

Vision and audio models generally ship a text GGUF plus a matching `mmproj`
GGUF. Import the text model first, open its details, and attach that projector.
Basalt asks llama.cpp which media types the pair supports before enabling them.

Model authors choose their own licenses and usage terms. Review them before
downloading or redistributing a model.

## Privacy and storage

Models and conversations stay in Basalt's Application Support container.
Model files are excluded from device backups to avoid filling iCloud storage.
Removing the app removes its local data. Network access is used only for a URL
the user explicitly imports or an opt-in web search. Web search sends the query
to the configured provider; the model still runs locally.

## Project layout

- `Basalt/` — app source and resources
- `BasaltTests/` and `BasaltUITests/` — unit and visual walkthrough coverage
- `project.yml` — reproducible Xcode project definition
- `Scripts/` — repository-local dependency and build tooling
- `.github/workflows/ios.yml` — build, test, and simulator capture pipeline

Architecture details live in [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md).

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).
Basalt is available under the [MIT License](LICENSE). llama.cpp and downloaded
models retain their respective licenses.
