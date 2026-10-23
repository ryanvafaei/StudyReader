# ADR-0008: Find Similar Highlights with on-device NLEmbedding

- Status: Accepted
- Date: 2026-10-23

## Context
Similarity must be free, private, and offline.

## Decision
`NLEmbedding.sentenceEmbedding(for:)` per detected language; Float32 vectors stored per highlight with model ID and source hash; brute-force cosine, threshold 0.55, top 5.

## Alternatives considered
Paid embedding APIs (excluded by scope); NLContextualEmbedding (needs pooling, heavier); vector DB libraries.

## Consequences
Languages without a sentence embedding are excluded from similarity.
