import RakerModel

/// Turns reviewed findings into a plan, choosing where each item goes.
public enum PlanBuilder {
    /// - Parameters:
    ///   - deleteRegenerable: The user agreed to skip the Trash for data that rebuilds itself.
    ///     Everything else always goes to the Trash.
    public static func plan(for findings: [Finding], deleteRegenerable: Bool, spaceBefore: VolumeSpace?) -> CleanupPlan {
        let items = findings.map { finding in
            PlanItem(
                finding: finding,
                destination: deleteRegenerable && finding.safety == .regenerable ? .delete : .trash
            )
        }
        return CleanupPlan(items: items, spaceBefore: spaceBefore)
    }
}
