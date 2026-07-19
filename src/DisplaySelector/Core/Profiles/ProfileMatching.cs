namespace DisplaySelector.Core.Profiles;

/// <summary>
/// Reboot-stable comparison of captured profile state, used to warn about saving a duplicate. Kept
/// out of the UI controller so it stays WinForms-free and unit-testable, and separate from the
/// tray's live-hardware match (<c>FindActiveProfileId</c>), which intentionally compares at a coarser
/// fidelity (stable-id set + primary only).
/// </summary>
internal static class ProfileMatching
{
    /// <summary>
    /// A reboot-stable fingerprint of a display capture. We deliberately do NOT hash the raw CCD
    /// blobs (<see cref="DisplayConfig.PathInfo"/>/<see cref="DisplayConfig.ModeInfo"/>): those embed
    /// adapter LUIDs that are not stable across reboots (see CLAUDE.md "here be dragons"), so blob
    /// equality would silently miss the same physical layout captured in a different boot session.
    /// Instead we key on the persisted stable identity (port-first StableId + EDID fallback) plus the
    /// descriptive per-display state. Sorted so target ordering differences don't produce false negatives.
    /// </summary>
    public static string DisplaySignature(DisplayConfig? display)
    {
        if (display is null)
        {
            return "<none>";
        }
        var parts = display.Targets
            .Select(t => $"{t.StableId}|{t.Edid}|{t.Primary}|{t.Resolution}|{t.Orientation}")
            .OrderBy(s => s, StringComparer.Ordinal);
        return string.Join(";", parts);
    }

    /// <summary>The first profile whose captured state matches the candidate, or null.</summary>
    public static Profile? FindDuplicate(IEnumerable<Profile> profiles, DisplayConfig? display, AudioConfig? audio)
    {
        // Fingerprint the candidate once, then compare each profile against it.
        var signature = DisplaySignature(display);
        return profiles.FirstOrDefault(p =>
            DisplaySignature(p.Display) == signature && p.Audio?.EndpointId == audio?.EndpointId);
    }

    /// <summary>
    /// The profile that matches the current live hardware, or null. This match is INTENTIONALLY
    /// coarser than <see cref="FindDuplicate"/>: it keys only on the set of connected display
    /// StableIds + which one is primary (ignoring EDID/resolution/orientation) plus the default audio
    /// endpoint, so a profile still reads as "active" when only resolution or orientation has drifted.
    /// A profile with no captured display matches on audio alone (audio-only profiles).
    /// </summary>
    public static Profile? FindActive(
        IEnumerable<Profile> profiles,
        IReadOnlyList<DisplayTarget> currentDisplays,
        string? currentAudioId)
    {
        var currentKeys = currentDisplays.Select(d => d.StableId).OrderBy(x => x).ToList();
        var currentPrimary = currentDisplays.FirstOrDefault(d => d.Primary)?.StableId;

        return profiles.FirstOrDefault(p =>
        {
            if (p.Audio is { } audio && audio.EndpointId != currentAudioId)
            {
                return false;
            }
            if (p.Display is { } display)
            {
                var keys = display.Targets.Select(t => t.StableId).OrderBy(x => x).ToList();
                var primary = display.Targets.FirstOrDefault(t => t.Primary)?.StableId;
                if (!keys.SequenceEqual(currentKeys) || primary != currentPrimary)
                {
                    return false;
                }
            }
            return true;
        });
    }
}
