param(
    [string]$OutputPath = "Basalt/Resources/Assets.xcassets/AppIcon.appiconset/BasaltIcon.png"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$workspace = Split-Path -Parent $PSScriptRoot
$target = [System.IO.Path]::GetFullPath((Join-Path $workspace $OutputPath))
$expectedRoot = [System.IO.Path]::GetFullPath($workspace) + [System.IO.Path]::DirectorySeparatorChar
if (-not $target.StartsWith($expectedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Icon output must remain inside the Basalt workspace."
}

$bitmap = [System.Drawing.Bitmap]::new(1024, 1024, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

try {
    $backgroundRect = [System.Drawing.Rectangle]::new(0, 0, 1024, 1024)
    $background = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        $backgroundRect,
        [System.Drawing.ColorTranslator]::FromHtml('#243033'),
        [System.Drawing.ColorTranslator]::FromHtml('#101517'),
        45.0
    )
    $graphics.FillRectangle($background, $backgroundRect)
    $background.Dispose()

    for ($index = 0; $index -lt 7; $index++) {
        $size = 860 - ($index * 100)
        $offset = (1024 - $size) / 2
        $alpha = [Math]::Max(2, 14 - ($index * 2))
        $halo = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb($alpha, 133, 157, 151))
        $graphics.FillEllipse($halo, $offset, $offset - 40, $size, $size)
        $halo.Dispose()
    }

    $shadowPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $shadowPath.AddEllipse(240, 770, 544, 105)
    $shadowBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(78, 0, 0, 0))
    $graphics.FillPath($shadowBrush, $shadowPath)
    $shadowBrush.Dispose()
    $shadowPath.Dispose()

    $stone = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $stone.StartFigure()
    $stone.AddBezier(512, 135, 650, 155, 775, 260, 806, 414)
    $stone.AddBezier(806, 414, 846, 612, 790, 770, 664, 846)
    $stone.AddBezier(664, 846, 566, 889, 427, 881, 335, 831)
    $stone.AddBezier(335, 831, 212, 756, 184, 588, 218, 414)
    $stone.AddBezier(218, 414, 247, 264, 372, 158, 512, 135)
    $stone.CloseFigure()

    $baseBrush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#344246'))
    $graphics.FillPath($baseBrush, $stone)
    $baseBrush.Dispose()

    $graphics.SetClip($stone)
    $layers = @(
        @{ Top = 170; Bottom = 300; Color = '#69787B' },
        @{ Top = 292; Bottom = 420; Color = '#4E6265' },
        @{ Top = 410; Bottom = 548; Color = '#354B4E' },
        @{ Top = 538; Bottom = 685; Color = '#2A3B3E' },
        @{ Top = 675; Bottom = 875; Color = '#202D30' }
    )
    foreach ($layer in $layers) {
        $brush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($layer.Color))
        $graphics.FillRectangle($brush, 120, $layer.Top, 784, $layer.Bottom - $layer.Top + 8)
        $brush.Dispose()
    }

    $seams = @(
        @{ Y = 294; Rise = -22; Color = '#A2B68D'; Width = 13 },
        @{ Y = 415; Rise = 18; Color = '#789097'; Width = 7 },
        @{ Y = 543; Rise = -13; Color = '#61777B'; Width = 6 },
        @{ Y = 681; Rise = 16; Color = '#B66A4E'; Width = 9 }
    )
    foreach ($seam in $seams) {
        $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
        $path.StartFigure()
        $path.AddBezier(138, $seam.Y, 330, $seam.Y + $seam.Rise, 654, $seam.Y - $seam.Rise, 886, $seam.Y + 4)
        $pen = [System.Drawing.Pen]::new([System.Drawing.ColorTranslator]::FromHtml($seam.Color), $seam.Width)
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $graphics.DrawPath($pen, $path)
        $pen.Dispose()
        $path.Dispose()
    }

    $glintPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $glintPath.StartFigure()
    $glintPath.AddBezier(302, 286, 354, 214, 417, 181, 485, 164)
    $glintPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(88, 221, 231, 219), 9)
    $glintPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $glintPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawPath($glintPen, $glintPath)
    $glintPen.Dispose()
    $glintPath.Dispose()

    $graphics.ResetClip()
    $outline = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(105, 209, 222, 213), 4)
    $graphics.DrawPath($outline, $stone)
    $outline.Dispose()
    $stone.Dispose()

    $directory = Split-Path -Parent $target
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    $bitmap.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $graphics.Dispose()
    $bitmap.Dispose()
}

Write-Output $target

