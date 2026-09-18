<#
.SYNOPSIS
  Converts an xLights .xmodel export into a DXF wiring guide for VCarve.

.DESCRIPTION
  Reads the per-node position table (CustomModelCompressed) out of an exported xLights
  Custom Model file and writes a DXF containing:

    - One polyline per physical LED string, in true wiring order (layers STRING_1,
      STRING_2, ...). This is the path a marker mounted on the spindle can trace to
      draw the wiring guide directly onto the prop.

    - One small circle per node, at its exact real-world position (layer NODE_POINTS).
      Select these in VCarve along with your circle+notch template (last) and run
      PGC_Replace_Circles to place accurately-positioned pixel holes - useful when a
      hand-drawn layout doesn't quite line up with the true node positions.

  All output is in real-world millimeters, at true 1:1 scale with the physical prop
  (taken directly from the model's widthmm/heightmm, not from its ScaleX/ScaleY).

.PARAMETER InputPath
  Path to the exported .xmodel file. In xLights: Layout tab, right-click the model,
  "Export model as..." (this is a single-model export, not a full show/layout export).

.PARAMETER OutputPath
  Path to write the .dxf file. Defaults to the input file's name/folder with a .dxf
  extension.

.PARAMETER PointRadius
  Radius, in mm, of the reference circles on the NODE_POINTS layer. Default 1.5mm.
  Purely cosmetic - PGC_Replace_Circles only uses each circle's center, not its size.

.EXAMPLE
  .\PGC_Wiring_Export.ps1 "C:\Users\ogbul\Desktop\Web L.xmodel"

.EXAMPLE
  .\PGC_Wiring_Export.ps1 -InputPath "Web L.xmodel" -OutputPath "Z:\Halloween\Web_L.dxf" -PointRadius 2.0

.NOTES
  First run may need:  powershell -ExecutionPolicy Bypass -File .\PGC_Wiring_Export.ps1 "file.xmodel"
  if Windows blocks unsigned local scripts by default on this machine.
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputPath,

    [Parameter(Position = 1)]
    [string]$OutputPath,

    [double]$PointRadius = 1.5
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $InputPath)) {
    Write-Error "Input file not found: $InputPath"
    exit 1
}

if (-not $OutputPath) {
    $OutputPath = [System.IO.Path]::ChangeExtension($InputPath, ".dxf")
}

# ---------------------------------------------------------------------------
# Parse the .xmodel XML
# ---------------------------------------------------------------------------

[xml]$xmodel = Get-Content -LiteralPath $InputPath -Raw

$models = @($xmodel.models.model)
if ($models.Count -eq 0 -or $null -eq $models[0]) {
    Write-Error "No <model> elements found in '$InputPath' - is this an xLights model export?"
    exit 1
}
if ($models.Count -gt 1) {
    Write-Warning "File contains $($models.Count) models - using the first one ('$($models[0].name)'). Export a single model at a time if you need a different one."
}
$model = $models[0]

$compressed = $model.CustomModelCompressed
if ([string]::IsNullOrWhiteSpace($compressed)) {
    Write-Error "Model '$($model.name)' has no CustomModelCompressed node data. Only Custom Models (Layout > Custom Model) export per-node positions this way."
    exit 1
}

$gridWidth  = [double]$model.CustomWidth
$gridHeight = [double]$model.CustomHeight
$widthMm    = [double]$model.widthmm
$heightMm   = [double]$model.heightmm
$pixelCount = [int]$model.PixelCount
$numStrings = [int]$model.CustomStrings

$cellW = $widthMm / $gridWidth
$cellH = $heightMm / $gridHeight

# ---------------------------------------------------------------------------
# Work out where each string starts/ends, from NodeStart1, NodeStart2, ...
# ---------------------------------------------------------------------------

$stringStarts = New-Object System.Collections.Generic.List[int]
for ($i = 1; $i -le $numStrings; $i++) {
    $val = $model."NodeStart$i"
    if ($val) {
        $stringStarts.Add([int]$val)
    }
}

if ($stringStarts.Count -ne $numStrings) {
    Write-Warning "Could not find NodeStart1..NodeStart$numStrings attributes - splitting $pixelCount nodes evenly across $numStrings string(s) instead. Check the result carefully."
    $stringStarts.Clear()
    $perString = [math]::Ceiling($pixelCount / $numStrings)
    for ($i = 0; $i -lt $numStrings; $i++) {
        $stringStarts.Add(($i * $perString) + 1)
    }
}

$sortedStarts = $stringStarts | Sort-Object
$stringEnds = New-Object System.Collections.Generic.List[int]
for ($i = 0; $i -lt $sortedStarts.Count; $i++) {
    if ($i -lt $sortedStarts.Count - 1) {
        $stringEnds.Add($sortedStarts[$i + 1] - 1)
    } else {
        $stringEnds.Add($pixelCount)
    }
}

# ---------------------------------------------------------------------------
# Parse "node,col,row;node,col,row;..." into real-world mm coordinates
# ---------------------------------------------------------------------------

$byNode = @{}
foreach ($triple in $compressed.Split(';')) {
    if ([string]::IsNullOrWhiteSpace($triple)) { continue }
    $parts = $triple.Split(',')
    $node = [int]$parts[0]
    $col  = [double]$parts[1]
    $row  = [double]$parts[2]
    $byNode[$node] = [PSCustomObject]@{ X = $col * $cellW; Y = $row * $cellH }
}

if ($byNode.Count -ne $pixelCount) {
    Write-Warning "Expected $pixelCount nodes but parsed $($byNode.Count). Continuing anyway."
}

# ---------------------------------------------------------------------------
# Build the DXF (classic R12-style POLYLINE/VERTEX/SEQEND + CIRCLE, so it
# opens in the widest range of CAD software including VCarve).
# ---------------------------------------------------------------------------

$sb = New-Object System.Text.StringBuilder

function Add-Line([string]$text) {
    [void]$sb.AppendLine($text)
}

function Add-Pair([string]$code, [string]$value) {
    Add-Line $code
    Add-Line $value
}

Add-Pair "0" "SECTION"
Add-Pair "2" "HEADER"
Add-Pair "9" '$INSUNITS'
Add-Pair "70" "4"
Add-Pair "0" "ENDSEC"

Add-Pair "0" "SECTION"
Add-Pair "2" "TABLES"
Add-Pair "0" "TABLE"
Add-Pair "2" "LAYER"
Add-Pair "70" ([string]($numStrings + 1))

$layerColors = @(1, 5, 3, 6, 2, 4)   # red, blue, green, magenta, yellow, cyan - cycles

for ($i = 0; $i -lt $numStrings; $i++) {
    $layerName = "STRING_$($i + 1)"
    $color = $layerColors[$i % $layerColors.Count]
    Add-Pair "0" "LAYER"
    Add-Pair "2" $layerName
    Add-Pair "70" "0"
    Add-Pair "62" ([string]$color)
    Add-Pair "6" "CONTINUOUS"
}

Add-Pair "0" "LAYER"
Add-Pair "2" "NODE_POINTS"
Add-Pair "70" "0"
Add-Pair "62" "7"
Add-Pair "6" "CONTINUOUS"

Add-Pair "0" "ENDTAB"
Add-Pair "0" "ENDSEC"

Add-Pair "0" "SECTION"
Add-Pair "2" "ENTITIES"

function Add-Polyline([string]$layer, $points) {
    Add-Pair "0" "POLYLINE"
    Add-Pair "8" $layer
    Add-Pair "66" "1"
    Add-Pair "70" "0"
    foreach ($p in $points) {
        Add-Pair "0" "VERTEX"
        Add-Pair "8" $layer
        Add-Pair "10" $p.X.ToString("F4")
        Add-Pair "20" $p.Y.ToString("F4")
        Add-Pair "30" "0.0"
    }
    Add-Pair "0" "SEQEND"
}

function Add-Circle([string]$layer, [double]$cx, [double]$cy, [double]$r) {
    Add-Pair "0" "CIRCLE"
    Add-Pair "8" $layer
    Add-Pair "10" $cx.ToString("F4")
    Add-Pair "20" $cy.ToString("F4")
    Add-Pair "30" "0.0"
    Add-Pair "40" $r.ToString("F4")
}

for ($i = 0; $i -lt $numStrings; $i++) {
    $layerName = "STRING_$($i + 1)"
    $points = New-Object System.Collections.Generic.List[object]
    for ($n = $sortedStarts[$i]; $n -le $stringEnds[$i]; $n++) {
        if ($byNode.ContainsKey($n)) {
            [void]$points.Add($byNode[$n])
        }
    }
    Add-Polyline -layer $layerName -points $points
}

foreach ($node in ($byNode.Keys | Sort-Object)) {
    $p = $byNode[$node]
    Add-Circle -layer "NODE_POINTS" -cx $p.X -cy $p.Y -r $PointRadius
}

Add-Pair "0" "ENDSEC"
Add-Pair "0" "EOF"

[System.IO.File]::WriteAllText($OutputPath, $sb.ToString())

Write-Host "Model: $($model.name)"
Write-Host "Wrote $($byNode.Count) node circles (NODE_POINTS) and $numStrings wiring polyline(s) to:"
Write-Host "  $OutputPath"
Write-Host "Grid cell size: $([math]::Round($cellW,3))mm x $([math]::Round($cellH,3))mm"
Write-Host "Bounding box: 0,0 to ${widthMm}mm, ${heightMm}mm"
Write-Host ""
$layerList = (1..$numStrings | ForEach-Object { "STRING_$_" }) -join ", "
Write-Host "Import into VCarve as Millimeters. Layers: $layerList, NODE_POINTS"
