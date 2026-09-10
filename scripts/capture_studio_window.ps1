# Captures the Roblox Studio main window to a PNG (icon capture pipeline, see
# docs/icon-capture.md). Captures only the Studio window, never the full screen.
# Usage: powershell -NoProfile -File scripts/capture_studio_window.ps1 <out.png>
param(
	[Parameter(Mandatory = $true)][string]$OutPath
)

$source = @'
using System;
using System.Runtime.InteropServices;
public class StudioWindowCapture {
	[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
	[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
	[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
	[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@
Add-Type -TypeDefinition $source
Add-Type -AssemblyName System.Drawing
[StudioWindowCapture]::SetProcessDPIAware() | Out-Null

$studio = Get-Process RobloxStudioBeta -ErrorAction Stop | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if ($null -eq $studio) {
	throw "Roblox Studio window not found"
}
$handle = $studio.MainWindowHandle
$rect = New-Object StudioWindowCapture+RECT
[StudioWindowCapture]::GetWindowRect($handle, [ref]$rect) | Out-Null
$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top

$bitmap = New-Object System.Drawing.Bitmap $width, $height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$deviceContext = $graphics.GetHdc()
# flag 2 = PW_RENDERFULLCONTENT, needed for the GPU-rendered viewport
$isSuccess = [StudioWindowCapture]::PrintWindow($handle, $deviceContext, 2)
$graphics.ReleaseHdc($deviceContext)
if (-not $isSuccess) {
	throw "PrintWindow failed"
}
$bitmap.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
"captured $($studio.MainWindowTitle) (${width}x${height}) to $OutPath"
