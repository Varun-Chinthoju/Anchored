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

        let optionalEvidence = evidence.filter { !$0.source.isExplicitRule }
        guard let highestRank = optionalEvidence.map({ ClassificationPolicy.rank(of: $0.source) }).min() else {
            return .neutral(evidence: evidence)
        }

        let candidates = optionalEvidence.filter {
            ClassificationPolicy.rank(of: $0.source) == highestRank
        }

        guard let first = candidates.first else {
            return .neutral(evidence: evidence)
        }

        if candidates.contains(where: { $0.label != first.label }) {
            return .neutral(reason: .conflictingEvidence, evidence: evidence)
        }

        let adjustedConfidence = adjustedConfidence(for: first, interactionSummary: interactionSummary)
        guard adjustedConfidence >= ClassificationPolicy.highConfidenceThreshold else {
            return .neutral(reason: .lowConfidence, evidence: evidence)
        }

        if first.source == .localModel || first.source == .cloudModel || first.source == .visualFallback {
            guard first.label == .productive else {
                return .neutral(reason: .optionalDistractionIsNonEnforcing, evidence: evidence)
            }
        }

        return ClassificationDecision(
            label: first.label,
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
