import Foundation

/// Sole policy owner for reducing classification evidence to a final decision.
///
/// The resolver is deliberately independent of FocusEngine, persistence, and
/// UI. Producers may be synchronous or asynchronous; they only contribute
/// evidence, while FocusEngine remains responsible for current-context and
/// state-transition checks.
final class ClassificationResolver {
    func resolve(
        _ evidence: [ClassificationEvidence],
        interactionSummary: InteractionSummary? = nil
    ) -> ClassificationDecision {
        guard !evidence.isEmpty else {
            return .neutral()
        }

        if let explicitDecision = resolveExplicitRules(evidence) {
            return explicitDecision
        }

        if let contextualDecision = resolveContextualEvidence(evidence, interactionSummary: interactionSummary) {
            return contextualDecision
        }

        let optionalEvidence = evidence.filter { !$0.source.isExplicitRule }
        let deterministicEvidence = optionalEvidence.filter {
            $0.source == .deterministicRule || $0.source == .heuristic
        }
        if !deterministicEvidence.isEmpty {
            return resolveOptionalEvidence(
                deterministicEvidence,
                interactionSummary: interactionSummary,
                evidenceTrace: evidence
            )
        }

        let modelEvidence = optionalEvidence.filter {
            $0.source == .localModel || $0.source == .cloudModel || $0.source == .visualFallback
        }
        return resolveModelEvidence(
            modelEvidence,
            interactionSummary: interactionSummary,
            evidenceTrace: evidence
        )
    }

    private func resolveContextualEvidence(
        _ evidence: [ClassificationEvidence],
        interactionSummary: InteractionSummary?
    ) -> ClassificationDecision? {
        let contextualEvidence = evidence.filter { $0.label == .contextual }
        guard !contextualEvidence.isEmpty else {
            return nil
        }

        let strongerNonExplicitEvidence = evidence.contains {
            !$0.source.isExplicitRule && ($0.label == .productive || $0.label == .distracting)
        }
        guard !strongerNonExplicitEvidence else {
            return nil
        }

        guard let first = contextualEvidence.max(by: { lhs, rhs in
            if lhs.confidence == rhs.confidence {
                return ClassificationPolicy.rank(of: lhs.source) > ClassificationPolicy.rank(of: rhs.source)
            }
            return lhs.confidence < rhs.confidence
        }) else {
            return nil
        }

        let adjustedConfidence = adjustedConfidence(for: first, interactionSummary: interactionSummary)
        return ClassificationDecision(
            label: .contextual,
            confidence: adjustedConfidence,
            source: first.source,
            reason: first.reason,
            evidence: evidence
        )
    }

    private func adjustedConfidence(
        for evidence: ClassificationEvidence,
        interactionSummary: InteractionSummary?
    ) -> Double {
        guard let interactionSummary,
              evidence.label == .productive,
              evidence.confidence >= ClassificationPolicy.lowConfidenceThreshold,
              interactionSummary.foregroundDuration >= 60,
              interactionSummary.idleDuration < interactionSummary.foregroundDuration * 0.5 else {
            return evidence.confidence
        }

        let boundedBoost = min(0.15, max(0, interactionSummary.foregroundDuration / 600 * 0.15))
        return min(1.0, evidence.confidence + boundedBoost)
    }

    private func resolveOptionalEvidence(
        _ evidence: [ClassificationEvidence],
        interactionSummary: InteractionSummary?,
        evidenceTrace: [ClassificationEvidence]
    ) -> ClassificationDecision {
        guard !evidence.isEmpty else {
            return .neutral(evidence: evidenceTrace)
        }

        guard let highestRank = evidence.map({ ClassificationPolicy.rank(of: $0.source) }).min() else {
            return .neutral(evidence: evidenceTrace)
        }

        let candidates = evidence.filter {
            ClassificationPolicy.rank(of: $0.source) == highestRank
        }

        guard let first = candidates.first else {
            return .neutral(evidence: evidenceTrace)
        }

        if candidates.contains(where: { $0.label != first.label }) {
            return .neutral(reason: .conflictingEvidence, evidence: evidenceTrace)
        }

        let adjustedConfidence = adjustedConfidence(for: first, interactionSummary: interactionSummary)
        guard adjustedConfidence >= ClassificationPolicy.highConfidenceThreshold else {
            return .neutral(reason: .lowConfidence, evidence: evidenceTrace)
        }

        return ClassificationDecision(
            label: first.label,
            confidence: adjustedConfidence,
            source: first.source,
            reason: first.reason,
            evidence: evidenceTrace
        )
    }

    private func resolveModelEvidence(
        _ evidence: [ClassificationEvidence],
        interactionSummary: InteractionSummary?,
        evidenceTrace: [ClassificationEvidence]
    ) -> ClassificationDecision {
        // Optional model output can still validate focus, but distracting
        // model evidence stays advisory so it never starts enforcement.
        guard !evidence.isEmpty else {
            return .neutral(evidence: evidenceTrace)
        }

        let productiveCandidates = evidence.filter { $0.label == .productive }
        let distractingCandidates = evidence.filter { $0.label == .distracting }

        if !productiveCandidates.isEmpty {
            guard distractingCandidates.isEmpty else {
                return .neutral(reason: .conflictingEvidence, evidence: evidenceTrace)
            }

            guard let first = productiveCandidates.min(by: {
                ClassificationPolicy.rank(of: $0.source) < ClassificationPolicy.rank(of: $1.source)
            }) else {
                return .neutral(evidence: evidenceTrace)
            }

            let adjustedConfidence = adjustedConfidence(for: first, interactionSummary: interactionSummary)
            guard adjustedConfidence >= ClassificationPolicy.highConfidenceThreshold else {
                return .neutral(reason: .lowConfidence, evidence: evidenceTrace)
            }

            return ClassificationDecision(
                label: first.label,
                confidence: adjustedConfidence,
                source: first.source,
                reason: first.reason,
                evidence: evidenceTrace
            )
        }

        if !distractingCandidates.isEmpty {
            return .neutral(reason: .optionalDistractionIsNonEnforcing, evidence: evidenceTrace)
        }

        return .neutral(reason: .lowConfidence, evidence: evidenceTrace)
    }

    private func resolveExplicitRules(_ evidence: [ClassificationEvidence]) -> ClassificationDecision? {
        let domainRules = evidence.filter { $0.source == .explicitDomainRule }
        if let domainDecision = resolveExplicitRuleGroup(domainRules, evidence: evidence) {
            return domainDecision
        }

        let appRules = evidence.filter { $0.source == .explicitAppRule }
        return resolveExplicitRuleGroup(appRules, evidence: evidence)
    }

    private func resolveExplicitRuleGroup(
        _ rules: [ClassificationEvidence],
        evidence: [ClassificationEvidence]
    ) -> ClassificationDecision? {
        guard !rules.isEmpty else { return nil }

        // Preserve the existing allow-wins behavior for legacy duplicate
        // entries. New corrections and editor changes reject contradictions.
        let selected = rules.first(where: { $0.label == .productive }) ?? rules.first!
        return ClassificationDecision(
            label: selected.label,
            confidence: selected.confidence,
            source: selected.source,
            reason: selected.reason,
            evidence: evidence
        )
    }
}
