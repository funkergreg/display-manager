using DisplaySelector.Core.Interop;

namespace DisplaySelector.Core;

/// <summary>
/// Best-effort working-set reduction for this mostly-idle tray app. After a burst of activity
/// (startup, an activation, a dialog) the CLR holds committed pages it won't reuse for a while;
/// compacting and asking Windows to trim the working set drops the resident footprint shown in
/// Task Manager. Trimmed pages fault back in on demand — a cheap trade for an app that idles
/// almost all the time. Purely an optimization: failures are swallowed.
/// </summary>
internal static class MemoryTuning
{
    public static void TrimWorkingSet()
    {
        try
        {
            // Reclaim the managed heap before we trim. Forced (not Optimized): this app allocates so
            // little that the GC's Optimized heuristic judges a collection "unproductive" and opts
            // out every time, so garbage from menu rebuilds/dialogs accumulates and committed memory
            // creeps upward during use. Forcing the collect keeps the heap flat. Still non-blocking
            // with no finalizer wait: this runs on the STA UI thread, and waiting on COM RCW
            // finalizers here would stall the tray and risk an STA marshaling deadlock. The heap is
            // tiny, so even this induced gen-2 collect is sub-millisecond.
            GC.Collect(2, GCCollectionMode.Forced, blocking: false);

            NativeMethods.SetProcessWorkingSetSize(NativeMethods.GetCurrentProcess(), -1, -1);
        }
        catch
        {
            // Never let an optimization affect the app.
        }
    }
}
