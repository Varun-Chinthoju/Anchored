# Local Classifier Evaluation

Wave 3 keeps local text classification behind an opt-in gate. The runtime is
`local-text-v1` in `Anchored/Engine/LocalTextClassifier.swift`; it is a small
deterministic feature scorer, not a shipped trained model. Fixture inputs are
sanitized `ContextSnapshot` identities and are versioned as
`local-text-fixtures-v1`.

## Evaluation contract

`LocalClassifierEvaluator` reports:

- false-distraction rate over productive fixtures;
- distracting precision;
- mean absolute calibration error for non-neutral predictions;
- p50 and p95 inference latency;
- CPU time and peak memory supplied by the offline harness.

The precision gate requires:

- false-distraction rate at or below 1%;
- distracting precision at or above 99%;
- calibration error at or below 0.15;
- p95 latency at or below 50 ms.

An empty fixture set never passes. A future trained artifact must carry its
own classifier and fixture version, pass this gate on anonymized fixtures, and
remain shadow-only until the report is reviewed. No local classifier result
may enforce distraction; only a high-confidence productive result may promote
the still-current neutral context through `ClassificationResolver`.

## Verification

Run the deterministic fixture and runtime tests with:

```bash
xcodegen generate
xcodebuild test -project Anchored.xcodeproj -scheme AnchoredTests \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:AnchoredTests/LocalTextClassifierTests
```

The fixture suite intentionally contains productive, distracting, conflicting,
and unknown contexts. It must not contain user-exported titles, full URLs,
screenshots, OCR, typed text, or interaction history.
