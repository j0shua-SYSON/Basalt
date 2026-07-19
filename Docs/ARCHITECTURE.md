# Architecture

Basalt is a native SwiftUI application with three deliberately small layers.

## App layer

`AppModel` owns navigation, selected model, conversations, and user-visible
operations. Views observe that single main-actor object. No inference pointer or
file handle enters the UI layer.

## Storage and import layer

`ModelStore` copies security-scoped GGUF documents into Application Support,
validates the `GGUF` header, records metadata in JSON, and excludes large model
files from backup. `HuggingFaceClient` normalizes Hugging Face URLs and downloads
to a temporary file before the same validation/import path runs.

`ConversationStore` persists compact JSON conversations separately from model
weights. Deleting a model does not silently delete conversations.

## Inference layer

`LlamaEngine` is an actor around the llama.cpp C API. Exactly one model is loaded
at a time. The engine uses memory mapping, device Metal layers, bounded context,
and a sampler chain. It applies the model's embedded chat template when
available and streams token events through `AsyncThrowingStream`.

When a matching multimodal projector is attached, the same actor initializes
llama.cpp `mtmd`, asks it whether the pair accepts vision and/or audio, and uses
its image/audio tokenizer and embedding evaluator. Thinking support is inferred
from GGUF identity and template metadata; reasoning tags stream into a separate
collapsible channel instead of being mixed into the final answer.

Opt-in retrieval is intentionally outside inference. `WebSearchClient` requests
five result snippets from Brave Search or a user-configured SearXNG endpoint.
The latest local prompt receives numbered context and the UI retains clickable
source cards.

The UI depends on `InferenceServing`, which lets previews and UI tests use a
deterministic in-process demo engine without shipping a test model.

## Dependency policy

The llama.cpp XCFramework and XcodeGen binary are pinned by version and SHA-256
in repository scripts. They are downloaded only into ignored folders under this
checkout. CI uses the same scripts as contributors.
