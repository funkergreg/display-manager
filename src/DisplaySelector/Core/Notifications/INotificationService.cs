namespace DisplaySelector.Core.Notifications;

public enum NotificationLevel
{
    Info,
    Warning,
}

/// <summary>User-facing notifications. Implementations replace the previous notification so a rapid
/// burst of actions collapses to the most recent (no Win11 notification-queue lag).</summary>
public interface INotificationService
{
    void Show(string message, NotificationLevel level = NotificationLevel.Info);

    /// <summary>Show a notification with one button per link, each opening its URL (falls back to text + URLs).</summary>
    void ShowWithLinks(string message, IReadOnlyList<(string Label, string Url)> links, NotificationLevel level = NotificationLevel.Info);
}
