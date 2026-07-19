namespace DisplaySelector.UI;

/// <summary>A small modal prompt for a single line of text (used for Save / Rename).</summary>
internal sealed class TextInputDialog : Form
{
    private readonly TextBox _input = new() { Dock = DockStyle.Fill };
    private readonly string _placeholder;

    public TextInputDialog(string title, string prompt, string initialValue = "", string placeholder = "")
    {
        Text = title;
        Icon = AppIcon.Window;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterScreen;
        MinimizeBox = false;
        MaximizeBox = false;
        ClientSize = new Size(360, 120);

        _placeholder = placeholder;

        var label = new Label { Text = prompt, Dock = DockStyle.Top, Height = 24 };
        _input.Text = initialValue;
        // Grey cue text shown in the empty box (clears on typing). Leaving the box untouched and
        // clicking OK accepts the placeholder as the value — the mouse-only "just save" path.
        _input.PlaceholderText = placeholder;
        _input.SelectAll();

        var ok = new Button { Text = "OK", DialogResult = DialogResult.OK, Width = 80 };
        var cancel = new Button { Text = "Cancel", DialogResult = DialogResult.Cancel, Width = 80 };
        AcceptButton = ok;
        CancelButton = cancel;

        var buttons = new FlowLayoutPanel
        {
            Dock = DockStyle.Bottom,
            FlowDirection = FlowDirection.RightToLeft,
            Height = 44,
            Padding = new Padding(8),
        };
        buttons.Controls.AddRange(new Control[] { ok, cancel });

        var inputPanel = new Panel { Dock = DockStyle.Fill, Padding = new Padding(8) };
        inputPanel.Controls.Add(_input);

        Controls.Add(inputPanel);
        Controls.Add(label);
        Controls.Add(buttons);
    }

    /// <summary>The trimmed text, or the placeholder default when the box is left blank.</summary>
    public string Value
    {
        get
        {
            var text = _input.Text.Trim();
            return text.Length > 0 ? text : _placeholder.Trim();
        }
    }

    /// <summary>
    /// Shows the dialog and returns the entered value. A blank box falls back to
    /// <paramref name="placeholder"/> (so a mouse-only OK accepts the suggested name); returns
    /// null only when cancelled or when the result is still empty (no placeholder given).
    /// </summary>
    public static string? Prompt(string title, string prompt, string initialValue = "", string placeholder = "")
    {
        using var dialog = new TextInputDialog(title, prompt, initialValue, placeholder);
        return dialog.ShowDialog() == DialogResult.OK && dialog.Value.Length > 0 ? dialog.Value : null;
    }
}
