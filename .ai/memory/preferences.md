# Preference Memory

### Engineering Mindset
- **Role**: Senior Software Engineer / Perfectionist.
- **Expectation**: Absolute fidelity to implementation plans, TDD rigor, and proactive verification.
- **Communication**: Concise, technical, and proactive. Use "Batch Reports" and "Quality Checkpoints."
- **Decision style**: Researches alternatives independently, shares findings with context (links, code refs), wants agent to give evaluated recommendations rather than open-ended options.

### Architectural Stances
- **Schema-agnostic over SDK-coupled**: Explicitly rejected Astral SDK's rigid schema in favor of composable LP base model + user-defined fields. This is a core design principle — never assume a fixed schema structure.
- **Spec compliance**: LP spec is authoritative. `snake_case` fields, full URI for `srs`, semver for `lp_version`. No shortcuts.
- **Standalone repo**: Prefers dedicated repos with clear naming (e.g., `location-protocol-dart` not `lp-dart`). Package under `DecentralizedGeo` org.
- **MVP scoping**: Comfortable deferring complexity (validation, delegated attest, batch ops) to Phase 2. Values a working thin slice over a broad incomplete one.

### Styling & Patterns
- Follow Dart's Effective Dart guidelines for naming and structure.
- Use barrel exports (`lib/location_protocol.dart`) to manage public API surface.
- Keep internal implementation in `lib/src/`.
- **Env Config**: Prefers `.env` + `.env.example` file pattern (inspired by [Astral SDK](https://github.com/DecentralizedGeo/astral-sdk/blob/main/.env.example)) over bash-exported environment variables for test secrets.

### Knowledge Architect Role
- **Goal**: Maintain the Agent Memory to ensure technical continuity and prevent "Project Reset."
- **Focus**: Capture codebase essence, architectural preferences, and procedural insights.

### Memory Management Rules
- **No Hallucination**: Store only facts verified by tests, docs, or user approval.
- **Brevity is Depth**: Use concise, punchy bullet points.
- **Forget the Noise**: Avoid temporary variables or minor lint fixes.
- **Selective Retention**: Identify 1-3 critical insights per batch.
- **Temporal Chaining**: In `episodic.md`, always link to the previous event ID.
