Add-Type -AssemblyName System.Drawing

$outDir = "D:\APPLE\ios_reader\Resources\Assets.xcassets\AppIcon.appiconset"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$size = 1024
$bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

$rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
$c1 = [System.Drawing.Color]::FromArgb(255, 58, 66, 82)
$c2 = [System.Drawing.Color]::FromArgb(255, 22, 26, 33)
$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, 60)
$g.FillRectangle($brush, $rect)

$pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(90, 255, 255, 255), 6)
$g.DrawRectangle($pen, 56, 56, 912, 912)

$fontBig = New-Object System.Drawing.Font("Microsoft YaHei", 430, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$fontSmall = New-Object System.Drawing.Font("Microsoft YaHei", 64, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)

$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 245, 243, 238))
$soft = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(190, 245, 243, 238))

$format = New-Object System.Drawing.StringFormat
$format.Alignment = [System.Drawing.StringAlignment]::Center
$format.LineAlignment = [System.Drawing.StringAlignment]::Center

$g.DrawString("阅", $fontBig, $white, (New-Object System.Drawing.RectangleF(0, 250, 1024, 520)), $format)
$g.DrawString("轻 阅 读", $fontSmall, $soft, (New-Object System.Drawing.RectangleF(0, 800, 1024, 120)), $format)

$master = Join-Path $outDir "AppIcon-1024.png"
$bmp.Save($master, [System.Drawing.Imaging.ImageFormat]::Png)

$targets = @(
    @{ name = "AppIcon-20@1x.png";  px = 20 },
    @{ name = "AppIcon-20@2x.png";  px = 40 },
    @{ name = "AppIcon-20@3x.png";  px = 60 },
    @{ name = "AppIcon-29@1x.png";  px = 29 },
    @{ name = "AppIcon-29@2x.png";  px = 58 },
    @{ name = "AppIcon-29@3x.png";  px = 87 },
    @{ name = "AppIcon-40@1x.png";  px = 40 },
    @{ name = "AppIcon-40@2x.png";  px = 80 },
    @{ name = "AppIcon-40@3x.png";  px = 120 },
    @{ name = "AppIcon-60@2x.png";  px = 120 },
    @{ name = "AppIcon-60@3x.png";  px = 180 },
    @{ name = "AppIcon-76@1x.png";  px = 76 },
    @{ name = "AppIcon-76@2x.png";  px = 152 },
    @{ name = "AppIcon-83.5@2x.png"; px = 167 }
)

foreach ($t in $targets) {
    $px = [int]$t.px
    $small = New-Object System.Drawing.Bitmap($px, $px, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $sg = [System.Drawing.Graphics]::FromImage($small)
    $sg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $sg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $sg.DrawImage($bmp, 0, 0, $px, $px)
    $small.Save((Join-Path $outDir $t.name), [System.Drawing.Imaging.ImageFormat]::Png)
    $sg.Dispose()
    $small.Dispose()
}

$g.Dispose()
$bmp.Dispose()
Write-Output "icons written to $outDir"
Get-ChildItem $outDir | Select-Object Name, Length
