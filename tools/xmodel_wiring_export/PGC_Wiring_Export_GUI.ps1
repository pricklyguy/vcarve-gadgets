<#
.SYNOPSIS
  Small desktop GUI front-end for PGC_Wiring_Export.ps1.

.DESCRIPTION
  Pure convenience wrapper - all the actual .xmodel parsing/DXF-generation
  logic lives in PGC_Wiring_Export.ps1 (must be in the same folder as this
  script). This just gives you file pickers and option boxes instead of a
  command line, then runs that script and shows its output.

.NOTES
  Launch via Install-Desktop-Shortcut.ps1 (one-time) for a normal desktop
  icon, or run directly:
    powershell -ExecutionPolicy Bypass -File .\PGC_Wiring_Export_GUI.ps1
#>

# Declare this process DPI-aware BEFORE creating any Forms. Without this,
# Windows bitmap-stretches the whole window on a scaled display (125%,
# 150%, etc.) instead of actually rendering at that size, which is what
# causes controls to appear shifted/overlapping even though their
# coordinates in code are correct.
Add-Type -Name Dpi -Namespace PGCWiringExport -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetProcessDPIAware();
"@
try { [PGCWiringExport.Dpi]::SetProcessDPIAware() | Out-Null } catch {}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$coreScript = Join-Path $PSScriptRoot "PGC_Wiring_Export.ps1"

if (-not (Test-Path -LiteralPath $coreScript)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Can't find PGC_Wiring_Export.ps1 next to this GUI script.`n`nExpected: $coreScript",
        "PGC Wiring Export",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

# ---------------------------------------------------------------------------
# Build the form
# ---------------------------------------------------------------------------

$form = New-Object System.Windows.Forms.Form
$form.Text = "PGC Wiring Export"

# WinForms applies its OWN per-control auto-scale transform based on the
# form's font, layered on top of (and independent from) Windows' system
# DPI scaling - that's what was still shifting/hiding controls even after
# declaring the process DPI-aware. Turning it off makes every control
# render at exactly the pixel coordinates given below, nothing more.
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)

$form.Size = New-Object System.Drawing.Size(600, 700)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$labelFont = New-Object System.Drawing.Font("Segoe UI", 9)
$form.Font = $labelFont

function New-Label($text, $x, $y, $width = 560) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.AutoSize = $false
    $lbl.Text = $text
    $lbl.Location = New-Object System.Drawing.Point($x, $y)
    $lbl.Size = New-Object System.Drawing.Size($width, 20)
    return $lbl
}

$y = 15

# --- Input file ---
$form.Controls.Add((New-Label "xLights .xmodel file:" 15 $y))
$y += 20
$inputBox = New-Object System.Windows.Forms.TextBox
$inputBox.Location = New-Object System.Drawing.Point(15, $y)
$inputBox.Size = New-Object System.Drawing.Size(460, 24)
$form.Controls.Add($inputBox)
$inputBrowse = New-Object System.Windows.Forms.Button
$inputBrowse.Text = "Browse..."
$inputBrowse.Location = New-Object System.Drawing.Point(485, $y - 1)
$inputBrowse.Size = New-Object System.Drawing.Size(90, 26)
$form.Controls.Add($inputBrowse)
$y += 40

# --- Output file ---
$form.Controls.Add((New-Label "Output .dxf file (optional - defaults next to the input file):" 15 $y))
$y += 20
$outputBox = New-Object System.Windows.Forms.TextBox
$outputBox.Location = New-Object System.Drawing.Point(15, $y)
$outputBox.Size = New-Object System.Drawing.Size(460, 24)
$form.Controls.Add($outputBox)
$outputBrowse = New-Object System.Windows.Forms.Button
$outputBrowse.Text = "Browse..."
$outputBrowse.Location = New-Object System.Drawing.Point(485, $y - 1)
$outputBrowse.Size = New-Object System.Drawing.Size(90, 26)
$form.Controls.Add($outputBrowse)
$y += 40

# --- Options row: three short fields side by side, each with its OWN
# label directly above it (same stacked label-then-field pattern as the
# input/output rows above, just three columns instead of one - avoids a
# long label sharing a row with an adjacent field). ---
$form.Controls.Add((New-Label "Hole diameter (mm):" 15 $y 180))
$form.Controls.Add((New-Label "Clearance margin (mm):" 210 $y 180))
$form.Controls.Add((New-Label "Point radius (mm):" 405 $y 170))
$y += 20

$holeBox = New-Object System.Windows.Forms.TextBox
$holeBox.Location = New-Object System.Drawing.Point(15, $y)
$holeBox.Size = New-Object System.Drawing.Size(170, 24)
$form.Controls.Add($holeBox)

$marginBox = New-Object System.Windows.Forms.TextBox
$marginBox.Text = "1.0"
$marginBox.Location = New-Object System.Drawing.Point(210, $y)
$marginBox.Size = New-Object System.Drawing.Size(170, 24)
$form.Controls.Add($marginBox)

$radiusBox = New-Object System.Windows.Forms.TextBox
$radiusBox.Text = "1.5"
$radiusBox.Location = New-Object System.Drawing.Point(405, $y)
$radiusBox.Size = New-Object System.Drawing.Size(160, 24)
$form.Controls.Add($radiusBox)
$y += 28

$form.Controls.Add((New-Label "Hole diameter blank = auto-detect from the model, 15mm fallback." 15 $y 560))
$y += 24

$orientCheck = New-Object System.Windows.Forms.CheckBox
$orientCheck.Text = "Rotate 270 + flip horizontal to match VCarve (every model so far has needed this)"
$orientCheck.Checked = $true
$orientCheck.Location = New-Object System.Drawing.Point(15, $y)
$orientCheck.Size = New-Object System.Drawing.Size(560, 24)
$form.Controls.Add($orientCheck)
$y += 40

# --- Generate button ---
$generateButton = New-Object System.Windows.Forms.Button
$generateButton.Text = "Generate DXF"
$generateButton.Location = New-Object System.Drawing.Point(15, $y)
$generateButton.Size = New-Object System.Drawing.Size(150, 32)
$generateButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($generateButton)

$openFolderButton = New-Object System.Windows.Forms.Button
$openFolderButton.Text = "Open Output Folder"
$openFolderButton.Location = New-Object System.Drawing.Point(175, $y)
$openFolderButton.Size = New-Object System.Drawing.Size(150, 32)
$openFolderButton.Enabled = $false
$form.Controls.Add($openFolderButton)
$y += 45

# --- Log box ---
$form.Controls.Add((New-Label "Output:" 15 $y))
$y += 20
$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(15, $y)
$logBox.Size = New-Object System.Drawing.Size(560, 300)
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$form.Controls.Add($logBox)

$script:lastOutputFolder = $null

# ---------------------------------------------------------------------------
# Behaviour
# ---------------------------------------------------------------------------

$inputBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "xLights Model (*.xmodel)|*.xmodel|All files (*.*)|*.*"
    $dlg.Title = "Select an xLights .xmodel file"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $inputBox.Text = $dlg.FileName
        if ([string]::IsNullOrWhiteSpace($outputBox.Text)) {
            $outputBox.Text = [System.IO.Path]::ChangeExtension($dlg.FileName, ".dxf")
        }
    }
})

$outputBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = "DXF file (*.dxf)|*.dxf"
    $dlg.Title = "Save DXF as"
    if (-not [string]::IsNullOrWhiteSpace($inputBox.Text)) {
        $dlg.InitialDirectory = Split-Path -Parent $inputBox.Text
        $dlg.FileName = [System.IO.Path]::GetFileNameWithoutExtension($inputBox.Text) + ".dxf"
    }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $outputBox.Text = $dlg.FileName
    }
})

$openFolderButton.Add_Click({
    if ($script:lastOutputFolder) {
        Start-Process explorer.exe $script:lastOutputFolder
    }
})

$generateButton.Add_Click({

    $inputPath = $inputBox.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($inputPath) -or -not (Test-Path -LiteralPath $inputPath)) {
        [System.Windows.Forms.MessageBox]::Show("Pick a valid .xmodel file first.", "PGC Wiring Export", "OK", "Warning") | Out-Null
        return
    }

    $argList = New-Object System.Collections.Generic.List[string]
    $argList.Add("-ExecutionPolicy"); $argList.Add("Bypass")
    $argList.Add("-NoProfile")
    $argList.Add("-File"); $argList.Add("`"$coreScript`"")
    $argList.Add("`"$inputPath`"")

    if (-not [string]::IsNullOrWhiteSpace($outputBox.Text)) {
        $argList.Add("-OutputPath"); $argList.Add("`"$($outputBox.Text.Trim())`"")
    }
    if (-not [string]::IsNullOrWhiteSpace($holeBox.Text)) {
        $argList.Add("-HoleDiameter"); $argList.Add($holeBox.Text.Trim())
    }
    if (-not [string]::IsNullOrWhiteSpace($marginBox.Text)) {
        $argList.Add("-ClearanceMargin"); $argList.Add($marginBox.Text.Trim())
    }
    if (-not [string]::IsNullOrWhiteSpace($radiusBox.Text)) {
        $argList.Add("-PointRadius"); $argList.Add($radiusBox.Text.Trim())
    }
    $argList.Add("-OrientToVCarve"); $argList.Add($(if ($orientCheck.Checked) { "true" } else { "false" }))

    $logBox.Text = "Running...`r`n"
    $generateButton.Enabled = $false
    $openFolderButton.Enabled = $false
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = ($argList -join " ")
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    $form.Cursor = [System.Windows.Forms.Cursors]::Default
    $generateButton.Enabled = $true

    $combined = $stdout
    if ($stderr) { $combined += "`r`n" + $stderr }
    $logBox.Text = $combined

    if ($proc.ExitCode -eq 0) {
        $outPath = $outputBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($outPath)) {
            $outPath = [System.IO.Path]::ChangeExtension($inputPath, ".dxf")
        }
        $script:lastOutputFolder = Split-Path -Parent $outPath
        $openFolderButton.Enabled = $true
        [System.Windows.Forms.MessageBox]::Show("Done. See the Output box for details.", "PGC Wiring Export", "OK", "Information") | Out-Null
    } else {
        [System.Windows.Forms.MessageBox]::Show("Something went wrong - see the Output box.", "PGC Wiring Export", "OK", "Error") | Out-Null
    }
})

# Force every control's layout to fully settle before the window is ever
# shown, in case the Browse button is catching a stale first-paint pass
# (a known WinForms quirk for controls added before the window handle
# exists) rather than an actual wrong coordinate.
$form.PerformLayout()

[void]$form.ShowDialog()
