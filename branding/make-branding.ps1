<#
.SYNOPSIS
    Regenerates the Veil OS wallpaper and boot-splash logo from branding/Logo.png.

.DESCRIPTION
    Windows PowerShell 5.1 + System.Drawing, no other dependencies.

    Wallpaper  -> files/system/usr/share/wallpapers/VeilOS/contents/images/1920x1080.png
      The logo is never scaled. Its edge artifacts are trimmed, the last text
      line ("CLIENT") is erased, and it is placed on a 1920x1080 canvas so that
      the emblem + wordmark sit in the centre. The canvas is filled with the
      logo's own edge colour and grain, and the logo's outer rim is feathered
      into it. The script then measures the seam and fails if it would show.

    Splash logo -> files/system/usr/share/plymouth/themes/spinner/watermark.png
      Emblem only, cut out along its own black outline, transparent outside,
      scaled DOWN to -SplashHeight pixels.

    Previews for eyeballing the result go to branding/preview/ (git-ignored).

.PARAMETER SplashHeight
    Height of the boot-splash logo in pixels. 96 is the largest round size that
    clears Plymouth's spinner and a status line on an 800x600 boot screen.
    Bazzite's own watermark is 43 px tall.

.PARAMETER CleanSplash
    Cut the emblem out with no glow at all. By default a thin band of the
    logo's red glow is kept around the emblem (as transparency), which makes
    the black outline readable on Plymouth's black background.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File branding\make-branding.ps1
#>
[CmdletBinding()]
param(
    [string]$Logo,
    [int]$SplashHeight = 96,
    [switch]$CleanSplash,
    [int]$HaloRadius = 24,
    [int]$CanvasWidth = 1920,
    [int]$CanvasHeight = 1080,
    [int]$Trim = 2,
    [int]$Feather = 32
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $Logo) { $Logo = Join-Path $PSScriptRoot 'Logo.png' }
$Logo = (Resolve-Path $Logo).Path

$wallpaperOut = Join-Path $repo 'files\system\usr\share\wallpapers\VeilOS\contents\images\1920x1080.png'
$splashOut    = Join-Path $repo 'files\system\usr\share\plymouth\themes\spinner\watermark.png'
$previewDir   = Join-Path $PSScriptRoot 'preview'
foreach ($d in @((Split-Path -Parent $wallpaperOut), (Split-Path -Parent $splashOut), $previewDir)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

Add-Type -AssemblyName System.Drawing

$source = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;

public class Band { public int Y0, Y1, X0, X1, Red, Dark; }

public static class VeilBranding
{
    // The logo is red and black artwork on a dark grey (~15,15,15) background.
    const int RedThreshold = 40;     // R - max(G,B) above this  -> artwork red
    const double DarkThreshold = 9;  // luma below this          -> artwork black
    const int Ring = 16;             // width of the border band used to sample the background

    // ---------------------------------------------------------------- pixel I/O
    // All buffers are BGRA, 4 bytes per pixel, top-down.
    public static byte[] Load(string path, out int w, out int h)
    {
        using (var bmp = new Bitmap(path))
        {
            w = bmp.Width; h = bmp.Height;
            var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            var buf = new byte[w * h * 4];
            for (int y = 0; y < h; y++)
                Marshal.Copy(new IntPtr(data.Scan0.ToInt64() + (long)y * data.Stride), buf, y * w * 4, w * 4);
            bmp.UnlockBits(data);
            return buf;
        }
    }

    public static void Save(string path, byte[] bgra, int w, int h, bool alpha)
    {
        var fmt = alpha ? PixelFormat.Format32bppArgb : PixelFormat.Format24bppRgb;
        using (var bmp = new Bitmap(w, h, fmt))
        {
            var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, fmt);
            int bpp = alpha ? 4 : 3;
            var row = new byte[w * bpp];
            for (int y = 0; y < h; y++)
            {
                for (int x = 0; x < w; x++)
                {
                    int i = (y * w + x) * 4;
                    row[x * bpp] = bgra[i]; row[x * bpp + 1] = bgra[i + 1]; row[x * bpp + 2] = bgra[i + 2];
                    if (alpha) row[x * bpp + 3] = bgra[i + 3];
                }
                Marshal.Copy(row, 0, new IntPtr(data.Scan0.ToInt64() + (long)y * data.Stride), row.Length);
            }
            bmp.UnlockBits(data);
            bmp.Save(path, ImageFormat.Png);
        }
    }

    static double Luma(byte[] p, int i) { return 0.114 * p[i] + 0.587 * p[i + 1] + 0.299 * p[i + 2]; }
    static bool IsRed(byte[] p, int i) { return p[i + 2] - Math.Max(p[i + 1], p[i]) > RedThreshold; }
    static bool IsDark(byte[] p, int i) { return Luma(p, i) < DarkThreshold; }
    static double Smooth(double t) { if (t <= 0) return 0; if (t >= 1) return 1; return t * t * (3 - 2 * t); }
    static byte Clamp(double v) { return (byte)Math.Max(0, Math.Min(255, Math.Round(v))); }

    // Small deterministic random generator, so the output is identical on every run.
    static uint seed;
    static int Next(int n) { seed = seed * 1664525u + 1013904223u; return (int)((seed >> 8) % (uint)n); }

    static byte[] Crop(byte[] p, int w, int x0, int y0, int cw, int ch)
    {
        var o = new byte[cw * ch * 4];
        for (int y = 0; y < ch; y++) Array.Copy(p, ((y0 + y) * w + x0) * 4, o, y * cw * 4, cw * 4);
        return o;
    }

    // ---------------------------------------------------------------- analysis
    // Horizontal bands of artwork (rows containing red or black pixels),
    // separated by at least 4 empty rows. For the Veil logo: emblem, "VEIL", "CLIENT".
    public static List<Band> FindBands(byte[] p, int w, int h)
    {
        var bands = new List<Band>();
        Band cur = null; int empty = 0;
        for (int y = 0; y < h; y++)
        {
            int red = 0, dark = 0, minx = w, maxx = -1;
            for (int x = 0; x < w; x++)
            {
                int i = (y * w + x) * 4;
                bool r = IsRed(p, i), d = !r && IsDark(p, i);
                if (r) red++; if (d) dark++;
                if (r || d) { if (x < minx) minx = x; if (x > maxx) maxx = x; }
            }
            if (maxx >= 0)
            {
                if (cur == null) { cur = new Band(); cur.Y0 = y; cur.X0 = minx; cur.X1 = maxx; }
                cur.Y1 = y; cur.X0 = Math.Min(cur.X0, minx); cur.X1 = Math.Max(cur.X1, maxx);
                cur.Red += red; cur.Dark += dark; empty = 0;
            }
            else if (cur != null && ++empty >= 4) { bands.Add(cur); cur = null; empty = 0; }
        }
        if (cur != null) bands.Add(cur);
        return bands;
    }

    // Pixels of the outer border band: the background as it is at the image's edges.
    static List<int> RingPixels(int w, int h)
    {
        var list = new List<int>();
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                if (x < Ring || x >= w - Ring || y < Ring || y >= h - Ring) list.Add((y * w + x) * 4);
        return list;
    }

    // The border band, but only from the sides that agree with each other.
    // One side of the logo (the bottom) is about a level brighter than the other
    // three; filling the canvas from all four would make the fill 0.3 levels
    // brighter than the logo's background. Sides more than 0.2 levels away from
    // the median side are left out.
    static List<int> FillPixels(byte[] p, int w, int h, StringBuilder log)
    {
        var sides = new List<int>[4];
        for (int s = 0; s < 4; s++) sides[s] = new List<int>();
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                if (y < Ring) sides[0].Add((y * w + x) * 4);
                else if (y >= h - Ring) sides[1].Add((y * w + x) * 4);
                else if (x < Ring) sides[2].Add((y * w + x) * 4);
                else if (x >= w - Ring) sides[3].Add((y * w + x) * 4);
            }
        var mean = new double[4];
        for (int s = 0; s < 4; s++) { double t = 0; foreach (int i in sides[s]) t += Luma(p, i); mean[s] = t / sides[s].Count; }
        var sorted = (double[])mean.Clone(); Array.Sort(sorted);
        double median = (sorted[1] + sorted[2]) / 2.0;
        string[] names = { "top", "bottom", "left", "right" };
        var list = new List<int>(); var used = new List<string>();
        for (int s = 0; s < 4; s++)
            if (Math.Abs(mean[s] - median) <= 0.2) { list.AddRange(sides[s]); used.Add(names[s]); }
        log.AppendLine(String.Format("border brightness: top {0:F2}, bottom {1:F2}, left {2:F2}, right {3:F2}; canvas grain taken from: {4}",
            mean[0], mean[1], mean[2], mean[3], String.Join(", ", used.ToArray())));
        if (list.Count == 0) throw new InvalidOperationException("The logo's four borders do not agree on a background colour.\n" + log);
        return list;
    }

    static int[] MedianColour(byte[] p, List<int> idx)
    {
        var res = new int[3];
        for (int c = 0; c < 3; c++)
        {
            var hist = new int[256];
            foreach (int i in idx) hist[p[i + c]]++;
            int acc = 0, v = 0;
            for (; v < 256; v++) { acc += hist[v]; if (acc * 2 >= idx.Count) break; }
            res[c] = v;
        }
        return res; // B, G, R
    }

    static double MeanLuma(byte[] p, int w, int x0, int y0, int x1, int y1)
    {
        double s = 0; int n = 0;
        for (int y = y0; y <= y1; y++) for (int x = x0; x <= x1; x++) { s += Luma(p, (y * w + x) * 4); n++; }
        return n == 0 ? 0 : s / n;
    }

    // Contrast-stretched copy for inspecting faint seams: (v - bg) * gain + 128.
    static byte[] Stretch(byte[] p, int[] bg, double gain)
    {
        var o = new byte[p.Length];
        for (int i = 0; i < p.Length; i += 4)
        {
            for (int c = 0; c < 3; c++) o[i + c] = Clamp((p[i + c] - bg[c]) * gain + 128);
            o[i + 3] = 255;
        }
        return o;
    }

    // ---------------------------------------------------------------- wallpaper
    public static string MakeWallpaper(string logo, string outPath, string previewDir,
                                       int cw, int ch, int trim, int feather)
    {
        var log = new StringBuilder();
        var fails = new List<string>();
        seed = 20261111u;

        int sw, sh;
        byte[] src = Load(logo, out sw, out sh);
        int w = sw - 2 * trim, h = sh - 2 * trim;
        byte[] img = Crop(src, sw, trim, trim, w, h);
        log.AppendLine(String.Format("source {0}x{1}, trimmed {2} px per side -> {3}x{4}", sw, sh, trim, w, h));

        var bands = FindBands(img, w, h);
        foreach (var b in bands)
            log.AppendLine(String.Format("  artwork band rows {0}..{1} cols {2}..{3} red={4} black={5}", b.Y0, b.Y1, b.X0, b.X1, b.Red, b.Dark));
        if (bands.Count != 3)
            throw new InvalidOperationException("Expected 3 artwork bands (emblem, wordmark, sub-line) but found " + bands.Count + ".\n" + log);
        Band emblem = bands[0], word = bands[1], sub = bands[2];
        if (sub.Red != 0)
            throw new InvalidOperationException("Expected the third band to be black text only.\n" + log);

        var ring = RingPixels(w, h);
        int[] bg = MedianColour(img, ring);
        double bgLuma = 0.114 * bg[0] + 0.587 * bg[1] + 0.299 * bg[2];
        log.AppendLine(String.Format("edge colour (median of the outer {0} px): R{1} G{2} B{3}", Ring, bg[2], bg[1], bg[0]));

        // -- erase the sub-line ("CLIENT") ------------------------------------
        // Each erased pixel is replaced by a real background pixel taken from the
        // SAME ROW, just left or right of the text, so brightness and grain match.
        const int core = 3, margin = 10, reach = 64;
        int gapAbove = sub.Y0 - word.Y1 - 1;
        int mTop = Math.Min(margin, gapAbove - 2);
        if (mTop < core + 1) throw new InvalidOperationException("Sub-line is too close to the wordmark to erase cleanly.\n" + log);
        int bx0 = sub.X0 - margin, bx1 = sub.X1 + margin, by0 = sub.Y0 - mTop, by1 = sub.Y1 + margin;
        if (bx0 - reach < 0 || bx1 + reach >= w || by1 >= h) throw new InvalidOperationException("Sub-line is too close to the image edge.\n" + log);
        byte[] orig = (byte[])img.Clone();
        for (int y = by0; y <= by1; y++)
        {
            for (int x = bx0; x <= bx1; x++)
            {
                int dx = Math.Max(Math.Max(sub.X0 - core - x, x - (sub.X1 + core)), 0);
                int dyT = Math.Max(sub.Y0 - core - y, 0), dyB = Math.Max(y - (sub.Y1 + core), 0);
                double fx = dx / (double)(margin - core);
                double fy = Math.Max(dyT / (double)(mTop - core), dyB / (double)(margin - core));
                double wgt = 1 - Smooth(Math.Max(fx, fy));
                int k = Next(2 * reach);
                int xs = k < reach ? bx0 - 1 - k : bx1 + 1 + (k - reach);
                int i = (y * w + x) * 4, j = (y * w + xs) * 4;
                for (int c = 0; c < 3; c++) img[i + c] = Clamp(orig[i + c] * (1 - wgt) + orig[j + c] * wgt);
            }
        }
        log.AppendLine(String.Format("erased sub-line: box cols {0}..{1} rows {2}..{3}", bx0, bx1, by0, by1));

        // -- canvas: edge colour with the logo's own grain --------------------
        // Every fill pixel is a random pixel from the logo's border band, so the
        // flat area has the same colour AND the same +-1 grain as the logo's background.
        var fill = FillPixels(orig, w, h, log);
        var canvas = new byte[cw * ch * 4];
        for (int i = 0; i < canvas.Length; i += 4)
        {
            int j = fill[Next(fill.Count)];
            canvas[i] = orig[j]; canvas[i + 1] = orig[j + 1]; canvas[i + 2] = orig[j + 2]; canvas[i + 3] = 255;
        }

        // -- place the artwork: emblem + wordmark centred, 1:1 ---------------
        int gx0 = Math.Min(emblem.X0, word.X0), gx1 = Math.Max(emblem.X1, word.X1);
        int gy0 = emblem.Y0, gy1 = word.Y1;
        int ox = (int)Math.Round(cw / 2.0 - ((gx0 + gx1) / 2.0 + 0.5));
        int oy = (int)Math.Round(ch / 2.0 - ((gy0 + gy1) / 2.0 + 0.5));
        if (ox < 0 || oy < 0 || ox + w > cw || oy + h > ch)
            throw new InvalidOperationException("The logo does not fit on the canvas without scaling.\n" + log);
        log.AppendLine(String.Format("placed at ({0},{1}) on {2}x{3}; emblem+wordmark centre = ({4:F1},{5:F1})",
            ox, oy, cw, ch, ox + (gx0 + gx1) / 2.0 + 0.5, oy + (gy0 + gy1) / 2.0 + 0.5));
        for (int y = 0; y < h; y++)
        {
            for (int x = 0; x < w; x++)
            {
                int d = Math.Min(Math.Min(x, w - 1 - x), Math.Min(y, h - 1 - y));
                double a = Smooth((d + 0.5) / feather);
                int i = (y * w + x) * 4, j = ((oy + y) * cw + ox + x) * 4;
                for (int c = 0; c < 3; c++) canvas[j + c] = Clamp(canvas[j + c] * (1 - a) + img[i + c] * a);
            }
        }

        // -- checks -------------------------------------------------------------
        // 1. Outer seam: brightness just inside the feather vs. just outside the logo, per side.
        int inA = feather, inB = feather + 15, outA = 4, outB = 19, skip = 64;
        double[] inside = {
            MeanLuma(canvas, cw, ox + skip, oy + inA, ox + w - 1 - skip, oy + inB),                 // top
            MeanLuma(canvas, cw, ox + skip, oy + h - 1 - inB, ox + w - 1 - skip, oy + h - 1 - inA), // bottom
            MeanLuma(canvas, cw, ox + inA, oy + skip, ox + inB, oy + h - 1 - skip),                 // left
            MeanLuma(canvas, cw, ox + w - 1 - inB, oy + skip, ox + w - 1 - inA, oy + h - 1 - skip)  // right
        };
        double[] outside = {
            MeanLuma(canvas, cw, ox + skip, oy - 1 - outB, ox + w - 1 - skip, oy - 1 - outA),
            MeanLuma(canvas, cw, ox + skip, oy + h + outA, ox + w - 1 - skip, oy + h + outB),
            MeanLuma(canvas, cw, ox - 1 - outB, oy + skip, ox - 1 - outA, oy + h - 1 - skip),
            MeanLuma(canvas, cw, ox + w + outA, oy + skip, ox + w + outB, oy + h - 1 - skip)
        };
        string[] names = { "top", "bottom", "left", "right" };
        for (int s = 0; s < 4; s++)
        {
            double diff = inside[s] - outside[s];
            bool ok = Math.Abs(diff) <= 1.0;
            log.AppendLine(String.Format("seam {0,-6}: inside {1:F2}  outside {2:F2}  diff {3:+0.00;-0.00}  {4}", names[s], inside[s], outside[s], diff, ok ? "ok" : "FAIL"));
            if (!ok) fails.Add("seam " + names[s]);
        }

        // 2. No step anywhere across the seam: largest jump between neighbouring
        //    row means (top/bottom) and column means (left/right), from outside to inside.
        double maxStep = 0;
        for (int s = 0; s < 4; s++)
        {
            double prev = 0; bool first = true;
            for (int t = -24; t < feather + 24; t++)
            {
                double m;
                if (s == 0) m = MeanLuma(canvas, cw, ox + skip, oy + t, ox + w - 1 - skip, oy + t);
                else if (s == 1) m = MeanLuma(canvas, cw, ox + skip, oy + h - 1 - t, ox + w - 1 - skip, oy + h - 1 - t);
                else if (s == 2) m = MeanLuma(canvas, cw, ox + t, oy + skip, ox + t, oy + h - 1 - skip);
                else m = MeanLuma(canvas, cw, ox + w - 1 - t, oy + skip, ox + w - 1 - t, oy + h - 1 - skip);
                if (!first) maxStep = Math.Max(maxStep, Math.Abs(m - prev));
                prev = m; first = false;
            }
        }
        bool stepOk = maxStep <= 0.5;
        log.AppendLine(String.Format("largest row/column step across the seam: {0:F3} levels  {1}", maxStep, stepOk ? "ok" : "FAIL"));
        if (!stepOk) fails.Add("seam step");

        // 3. Erased strip: no text left, and it matches the background around it.
        double minL = 255, maxL = 0;
        for (int y = by0; y <= by1; y++) for (int x = bx0; x <= bx1; x++) { double l = Luma(img, (y * w + x) * 4); if (l < minL) minL = l; if (l > maxL) maxL = l; }
        double stripMean = MeanLuma(img, w, sub.X0, sub.Y0, sub.X1, sub.Y1);
        double aroundMean = (MeanLuma(img, w, bx0 - 40, by0, bx0 - 1, by1) + MeanLuma(img, w, bx1 + 1, by0, bx1 + 40, by1)
                           + MeanLuma(img, w, bx0, by1 + 1, bx1, by1 + 12)) / 3.0;
        bool stripOk = Math.Abs(stripMean - aroundMean) <= 1.0 && minL >= bgLuma - 4 && maxL <= bgLuma + 4;
        log.AppendLine(String.Format("erased strip: mean {0:F2} vs surroundings {1:F2}; darkest {2:F1}, brightest {3:F1} (background {4:F1})  {5}",
            stripMean, aroundMean, minL, maxL, bgLuma, stripOk ? "ok" : "FAIL"));
        if (!stripOk) fails.Add("erased strip");

        // -- output + previews ----------------------------------------------------
        Save(outPath, canvas, cw, ch, false);
        byte[] st = Stretch(canvas, bg, 8);
        Save(System.IO.Path.Combine(previewDir, "wallpaper-stretched.png"), st, cw, ch, false);
        // 100% crops of the stretched image: top-left corner of the logo area, bottom edge, erased strip.
        Save(System.IO.Path.Combine(previewDir, "wallpaper-stretched-corner.png"), Crop(st, cw, ox - 150, oy - 150, 600, 450), 600, 450, false);
        Save(System.IO.Path.Combine(previewDir, "wallpaper-stretched-bottom.png"), Crop(st, cw, ox + w / 2 - 400, oy + h - 220, 800, 300), 800, 300, false);
        Save(System.IO.Path.Combine(previewDir, "wallpaper-stretched-strip.png"), Crop(st, cw, ox + bx0 - 150, oy + by0 - 110, (bx1 - bx0) + 300, (by1 - by0) + 170), (bx1 - bx0) + 300, (by1 - by0) + 170, false);
        Save(System.IO.Path.Combine(previewDir, "wallpaper-strip.png"), Crop(canvas, cw, ox + bx0 - 150, oy + by0 - 110, (bx1 - bx0) + 300, (by1 - by0) + 170), (bx1 - bx0) + 300, (by1 - by0) + 170, false);

        log.AppendLine("wrote " + outPath);
        if (fails.Count > 0) throw new InvalidOperationException("WALLPAPER CHECKS FAILED: " + String.Join(", ", fails.ToArray()) + "\n" + log);
        return log.ToString();
    }

    // ---------------------------------------------------------------- splash logo
    public static string MakeSplash(string logo, string outPath, string previewDir,
                                    int outH, bool glow, int halo, int trim)
    {
        var log = new StringBuilder();
        int sw, sh;
        byte[] src = Load(logo, out sw, out sh);
        int w = sw - 2 * trim, h = sh - 2 * trim;
        byte[] img = Crop(src, sw, trim, trim, w, h);
        var bands = FindBands(img, w, h);
        if (bands.Count < 2) throw new InvalidOperationException("Could not find the emblem and wordmark bands.");
        Band emblem = bands[0], word = bands[1];
        int[] bg = MedianColour(img, RingPixels(w, h));

        // Margin around the emblem, in source pixels. Even without the glow it must
        // be wider than one output pixel, or the emblem's tips land on the image border.
        int pad = (glow ? halo : 4) + 2;
        int room = word.Y0 - emblem.Y1 - 2;   // rows free between the emblem's tip and the wordmark
        if (glow && halo + 2 > room)
            throw new InvalidOperationException("Halo of " + halo + " px would reach the wordmark (only " + room + " px free below the emblem).");
        int cx0 = emblem.X0 - pad, cy0 = emblem.Y0 - pad;
        int cw = emblem.X1 - emblem.X0 + 1 + 2 * pad, ch = emblem.Y1 - emblem.Y0 + 1 + 2 * pad;
        byte[] c = Crop(img, w, cx0, cy0, cw, ch);
        log.AppendLine(String.Format("emblem rows {0}..{1} cols {2}..{3} ({4}x{5}); crop {6}x{7}",
            emblem.Y0 + trim, emblem.Y1 + trim, emblem.X0 + trim, emblem.X1 + trim, emblem.X1 - emblem.X0 + 1, emblem.Y1 - emblem.Y0 + 1, cw, ch));

        // 1. Silhouette = the emblem's black outline plus everything it encloses.
        //    The outline is what separates the artwork from the glow: the glow right
        //    next to the emblem is itself fairly red, so "is this pixel red?" cannot
        //    tell the two apart, but "is this pixel inside the outline?" can.
        int n = cw * ch;
        var S = new bool[n];
        for (int i = 0; i < n; i++) S[i] = IsDark(c, i * 4);
        // Drop black specks smaller than 30 px that are not part of the outline.
        var label = new int[n]; var queue = new int[n];
        for (int i = 0; i < n; i++)
        {
            if (!S[i] || label[i] != 0) continue;
            int head = 0, tail = 0; queue[tail++] = i; label[i] = 1;
            while (head < tail)
            {
                int q = queue[head++], qx = q % cw, qy = q / cw;
                for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++)
                {
                    int nx = qx + dx, ny = qy + dy; if (nx < 0 || ny < 0 || nx >= cw || ny >= ch) continue;
                    int ni = ny * cw + nx; if (S[ni] && label[ni] == 0) { label[ni] = 1; queue[tail++] = ni; }
                }
            }
            if (tail < 30) for (int k = 0; k < tail; k++) S[queue[k]] = false;
        }
        // Flood-fill the outside starting from the crop's border; whatever the
        // flood cannot reach is enclosed by the outline and belongs to the emblem.
        var outside = new bool[n]; int oh = 0, ot = 0;
        for (int x = 0; x < cw; x++) { foreach (int y in new[] { 0, ch - 1 }) { int i = y * cw + x; if (!S[i] && !outside[i]) { outside[i] = true; queue[ot++] = i; } } }
        for (int y = 0; y < ch; y++) { foreach (int x in new[] { 0, cw - 1 }) { int i = y * cw + x; if (!S[i] && !outside[i]) { outside[i] = true; queue[ot++] = i; } } }
        while (oh < ot)
        {
            int q = queue[oh++], qx = q % cw, qy = q / cw;
            int[] nxs = { qx - 1, qx + 1, qx, qx }, nys = { qy, qy, qy - 1, qy + 1 };
            for (int k = 0; k < 4; k++)
            {
                if (nxs[k] < 0 || nys[k] < 0 || nxs[k] >= cw || nys[k] >= ch) continue;
                int ni = nys[k] * cw + nxs[k]; if (!S[ni] && !outside[ni]) { outside[ni] = true; queue[ot++] = ni; }
            }
        }
        int filled = 0, leaked = 0, glowMax = 0;
        for (int i = 0; i < n; i++)
        {
            if (!S[i] && !outside[i]) { S[i] = true; filled++; }
            else if (outside[i])
            {
                // Saturated artwork red found OUTSIDE the outline means the outline has a
                // gap and the flood leaked into the emblem. The glow never gets this red.
                int rd = c[i * 4 + 2] - Math.Max(c[i * 4 + 1], c[i * 4]);
                if (rd > 90) leaked++;
                if (rd > glowMax) glowMax = rd;
            }
        }
        log.AppendLine(String.Format("pixels enclosed by the outline: {0}; reddest glow pixel outside it: R-G = {1}", filled, glowMax));
        if (leaked > 0)
            throw new InvalidOperationException("The emblem's black outline is not closed (" + leaked + " artwork-red pixels are reachable from outside).\n" + log);

        // 2. Distance from the silhouette (3-4 chamfer), for the optional glow band.
        var dist = new int[n];
        for (int i = 0; i < n; i++) dist[i] = S[i] ? 0 : 1000000;
        for (int y = 0; y < ch; y++) for (int x = 0; x < cw; x++)
        {
            int i = y * cw + x, d = dist[i];
            if (x > 0) d = Math.Min(d, dist[i - 1] + 3);
            if (y > 0) { d = Math.Min(d, dist[i - cw] + 3); if (x > 0) d = Math.Min(d, dist[i - cw - 1] + 4); if (x < cw - 1) d = Math.Min(d, dist[i - cw + 1] + 4); }
            dist[i] = d;
        }
        for (int y = ch - 1; y >= 0; y--) for (int x = cw - 1; x >= 0; x--)
        {
            int i = y * cw + x, d = dist[i];
            if (x < cw - 1) d = Math.Min(d, dist[i + 1] + 3);
            if (y < ch - 1) { d = Math.Min(d, dist[i + cw] + 3); if (x < cw - 1) d = Math.Min(d, dist[i + cw + 1] + 4); if (x > 0) d = Math.Min(d, dist[i + cw - 1] + 4); }
            dist[i] = d;
        }

        // 3. Premultiplied RGBA: the emblem is opaque with its original colours;
        //    the glow (optional) is whatever is brighter than the background, fading
        //    to nothing at 'halo' px from the emblem; everything else is transparent.
        var pm = new double[n * 4];
        for (int i = 0; i < n; i++)
        {
            if (S[i]) { pm[i * 4] = c[i * 4]; pm[i * 4 + 1] = c[i * 4 + 1]; pm[i * 4 + 2] = c[i * 4 + 2]; pm[i * 4 + 3] = 255; }
            else if (glow)
            {
                double f = 1 - Smooth((dist[i] / 3.0) / halo);
                if (f <= 0) continue;
                double b = Math.Max(0, c[i * 4] - bg[0] - 1) * f, g = Math.Max(0, c[i * 4 + 1] - bg[1] - 1) * f, r = Math.Max(0, c[i * 4 + 2] - bg[2] - 1) * f;
                pm[i * 4] = b; pm[i * 4 + 1] = g; pm[i * 4 + 2] = r; pm[i * 4 + 3] = Math.Max(r, Math.Max(g, b));
            }
        }

        // 4. Scale DOWN by area averaging (never up).
        double scale = outH / (double)ch;
        if (scale > 1) throw new InvalidOperationException("Requested splash height would upscale the emblem.");
        int ow = (int)Math.Round(cw * scale);
        double[] tmp = Resample(pm, cw, ch, ow, true);
        double[] fin = Resample(tmp, ow, ch, outH, false);
        var o = new byte[ow * outH * 4];
        double borderAlpha = 0;
        for (int i = 0; i < ow * outH; i++)
        {
            double a = fin[i * 4 + 3];
            if (a > 0.5) for (int k = 0; k < 3; k++) o[i * 4 + k] = Clamp(fin[i * 4 + k] * 255.0 / a);
            o[i * 4 + 3] = Clamp(a);
            int x = i % ow, y = i / ow;
            if (x == 0 || y == 0 || x == ow - 1 || y == outH - 1) borderAlpha = Math.Max(borderAlpha, o[i * 4 + 3]);
        }
        Save(outPath, o, ow, outH, true);
        log.AppendLine(String.Format("splash logo {0}x{1} (scale {2:F3}, emblem itself {3:F0} px tall), glow {4}", ow, outH, scale, (emblem.Y1 - emblem.Y0 + 1) * scale, glow ? "kept (" + halo + " px band)" : "removed"));
        log.AppendLine(String.Format("largest alpha on the image border: {0} of 255 (0 = no visible box around the logo)", borderAlpha));
        log.AppendLine("wrote " + outPath);

        string tag = glow ? "glow" : "clean";
        Save(System.IO.Path.Combine(previewDir, "splash-" + tag + "-on-black-6x.png"), Zoom(Over(o, ow, outH, 0, 0, 0), ow, outH, 6), ow * 6, outH * 6, false);
        Save(System.IO.Path.Combine(previewDir, "splash-" + tag + "-on-grey-6x.png"), Zoom(Over(o, ow, outH, 96, 96, 96), ow, outH, 6), ow * 6, outH * 6, false);
        foreach (int[] scr in new[] { new[] { 1920, 1080 }, new[] { 1024, 768 }, new[] { 800, 600 } })
            Save(System.IO.Path.Combine(previewDir, "splash-" + tag + "-mock-" + scr[0] + "x" + scr[1] + ".png"), Mock(o, ow, outH, scr[0], scr[1]), scr[0], scr[1], false);
        if (borderAlpha > 8) throw new InvalidOperationException("SPLASH CHECK FAILED: the logo touches the edge of its image (alpha " + borderAlpha + ").\n" + log);
        return log.ToString();
    }

    // Box-filter resample along one axis (horizontal: w -> nw, vertical: h -> nh).
    static double[] Resample(double[] p, int w, int h, int target, bool horizontal)
    {
        int nw = horizontal ? target : w, nh = horizontal ? h : target;
        int srcLen = horizontal ? w : h, lines = horizontal ? h : w;
        double ratio = srcLen / (double)target;
        var o = new double[nw * nh * 4];
        for (int line = 0; line < lines; line++)
        {
            for (int t = 0; t < target; t++)
            {
                double a = t * ratio, b = (t + 1) * ratio;
                for (int s = (int)Math.Floor(a); s < Math.Ceiling(b) && s < srcLen; s++)
                {
                    double wgt = (Math.Min(b, s + 1) - Math.Max(a, s)) / ratio;
                    int si = horizontal ? (line * w + s) * 4 : (s * w + line) * 4;
                    int di = horizontal ? (line * nw + t) * 4 : (t * nw + line) * 4;
                    for (int k = 0; k < 4; k++) o[di + k] += p[si + k] * wgt;
                }
            }
        }
        return o;
    }

    // Composite straight-alpha RGBA over a solid colour.
    static byte[] Over(byte[] p, int w, int h, int r, int g, int b)
    {
        var o = new byte[w * h * 4];
        for (int i = 0; i < w * h * 4; i += 4)
        {
            double a = p[i + 3] / 255.0;
            o[i] = Clamp(p[i] * a + b * (1 - a)); o[i + 1] = Clamp(p[i + 1] * a + g * (1 - a)); o[i + 2] = Clamp(p[i + 2] * a + r * (1 - a)); o[i + 3] = 255;
        }
        return o;
    }

    static byte[] Zoom(byte[] p, int w, int h, int z)
    {
        var o = new byte[w * z * h * z * 4];
        for (int y = 0; y < h * z; y++) for (int x = 0; x < w * z; x++) Array.Copy(p, ((y / z) * w + x / z) * 4, o, (y * w * z + x) * 4, 4);
        return o;
    }

    // What Plymouth's spinner theme would draw on a black screen of the given size:
    // 32x32 spinner centred at 70% height, a status line 10 px below it, and the
    // logo with its top edge at 0.96 * (screen height - logo height).
    static byte[] Mock(byte[] logo, int lw, int lh, int W, int H)
    {
        var o = new byte[W * H * 4];
        for (int i = 3; i < o.Length; i += 4) o[i] = 255;
        int sx = W / 2 - 16, sy = (int)Math.Round(0.7 * H - 16);
        for (int y = 0; y < 32; y++) for (int x = 0; x < 32; x++)
        {
            double d = Math.Sqrt((x - 15.5) * (x - 15.5) + (y - 15.5) * (y - 15.5));
            if (d >= 11 && d <= 15) { int i = ((sy + y) * W + sx + x) * 4; o[i] = o[i + 1] = o[i + 2] = 200; }
        }
        int my = sy + 32 + 10;
        for (int y = 0; y < 20; y++) for (int x = W / 2 - 150; x < W / 2 + 150; x++)
        {
            if (y < 4 || y > 15) continue;
            int i = ((my + y) * W + x) * 4; o[i] = o[i + 1] = o[i + 2] = 110;
        }
        int wx = (int)Math.Round((W - lw) * 0.5), wy = (int)Math.Round((H - lh) * 0.96);
        for (int y = 0; y < lh; y++) for (int x = 0; x < lw; x++)
        {
            int si = (y * lw + x) * 4, di = ((wy + y) * W + wx + x) * 4;
            double a = logo[si + 3] / 255.0;
            for (int k = 0; k < 3; k++) o[di + k] = Clamp(logo[si + k] * a + o[di + k] * (1 - a));
        }
        return o;
    }
}
'@
Add-Type -TypeDefinition $source -ReferencedAssemblies System.Drawing

try {
    Write-Host '== Wallpaper ==' -ForegroundColor Cyan
    [VeilBranding]::MakeWallpaper($Logo, $wallpaperOut, $previewDir, $CanvasWidth, $CanvasHeight, $Trim, $Feather)
    Write-Host '== Boot-splash logo ==' -ForegroundColor Cyan
    [VeilBranding]::MakeSplash($Logo, $splashOut, $previewDir, $SplashHeight, (-not $CleanSplash), $HaloRadius, $Trim)
    Write-Host "Previews are in $previewDir" -ForegroundColor Green
}
catch {
    Write-Host $_.Exception.InnerException.Message -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
