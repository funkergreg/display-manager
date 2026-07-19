using System.Diagnostics;
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
            // Nudge a background collect so more of the managed heap is reclaimable before we trim.
            // Non-blocking and no finalizer wait: this runs on the STA UI thread, and waiting on COM
            // RCW finalizers here would stall the tray and risk an STA marshaling deadlock.
            GC.Collect(2, GCCollectionMode.Optimized, blocking: false);

            NativeMethods.SetProcessWorkingSetSize(NativeMethods.GetCurrentProcess(), -1, -1);
        }
        catch
        {
            // Never let an optimization affect the app.
        }
    }

    /// <summary>
    /// One-line memory snapshot for the log. Separates the managed heap (a real leak grows this
    /// monotonically) from the process working set (which sawtooths as the trim drops pages that
    /// then fault back in) so we can tell a leak apart from mere working-set churn.
    /// </summary>
    public static string Snapshot()
    {
        try
        {
            using var p = Process.GetCurrentProcess();
            var gc = GC.GetGCMemoryInfo();
            long mb = 1024 * 1024;
            return $"WorkingSet={p.WorkingSet64 / mb}MB Private={p.PrivateMemorySize64 / mb}MB " +
                   $"ManagedHeap={GC.GetTotalMemory(false) / mb}MB GCHeap={gc.HeapSizeBytes / mb}MB " +
                   $"Committed={gc.TotalCommittedBytes / mb}MB " +
                   $"GC(g0/g1/g2)={GC.CollectionCount(0)}/{GC.CollectionCount(1)}/{GC.CollectionCount(2)}";
        }
        catch (Exception ex)
        {
            return $"(memory snapshot failed: {ex.Message})";
        }
    }
}
