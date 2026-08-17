# extract_pdf_text.ps1 - pure .NET PDF text extractor (no third-party libs)
# Usage: & scripts/extract_pdf_text.ps1 -Path <pdf> [-Out <txt>]
# Supports: FlateDecode inflation, WinAnsi/MacRoman/Standard encodings, ToUnicode CMap (bfchar/bfrange)
param(
  [Parameter(Mandatory = $true)][string]$Path,
  [string]$Out = ""
)

$ErrorActionPreference = "Stop"
$ascii = [System.Text.Encoding]::ASCII
$bytes = [System.IO.File]::ReadAllBytes($Path)

# ---- helpers -------------------------------------------------------------
function Find-Bytes([byte[]]$hay, [byte[]]$needle, [int]$start) {
  for ($i = $start; $i -le $hay.Length - $needle.Length; $i++) {
    $ok = $true
    for ($j = 0; $j -lt $needle.Length; $j++) {
      if ($hay[$i + $j] -ne $needle[$j]) { $ok = $false; break }
    }
    if ($ok) { return $i }
  }
  return -1
}

# ---- parse objects: num -> @{ dict; sStart; sEnd } -----------------------
$endObjB = $ascii.GetBytes("endobj")
$endStreamB = $ascii.GetBytes("endstream")
$objects = @{}
$objMatches = [regex]::Matches($ascii.GetString($bytes), '(\d+)\s+0\s+obj')
foreach ($m in $objMatches) {
  $num = [int]$m.Groups[1].Value
  if ($objects.ContainsKey($num)) { continue }
  $objStart = $m.Index + $m.Length
  $endObj = Find-Bytes $bytes $endObjB $objStart
  if ($endObj -lt 0) { continue }
  $seg = $ascii.GetString($bytes, $objStart, $endObj - $objStart)
  $sIdx = $seg.IndexOf("stream")
  if ($sIdx -lt 0) {
    $objects[$num] = @{ dict = $seg; sStart = -1; sEnd = -1 }
    continue
  }
  $dict = $seg.Substring(0, $sIdx)
  $dataStart = $objStart + $sIdx + 6   # length of "stream"
  if ($bytes[$dataStart] -eq 13 -and $bytes[$dataStart + 1] -eq 10) { $dataStart += 2 }
  elseif ($bytes[$dataStart] -eq 10) { $dataStart += 1 }
  $eIdx = Find-Bytes $bytes $endStreamB $dataStart
  if ($eIdx -lt 0) { continue }
  $objects[$num] = @{ dict = $dict; sStart = $dataStart; sEnd = $eIdx }
}

function Inflate([byte[]]$data) {
  if ($null -eq $data -or $data.Length -lt 4) { return $null }
  $start = 0
  if ($data[0] -eq 0x78) { $start = 2 }
  try {
    $ms = New-Object System.IO.MemoryStream(,$data)
    $ms.Position = $start
    $ds = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
    $out = New-Object System.IO.MemoryStream
    $ds.CopyTo($out)
    $ds.Dispose(); $ms.Dispose()
    return $out.ToArray()
  } catch { return $null }
}

function Get-StreamText([int]$num) {
  if (-not $objects.ContainsKey($num)) { return $null }
  $o = $objects[$num]
  if ($o.sStart -lt 0) { return $null }
  $len = $o.sEnd - $o.sStart
  if ($len -le 0) { return $null }
  $data = New-Object byte[] $len
  [Array]::Copy($bytes, $o.sStart, $data, 0, $len)
  if ($o.dict -match '/FlateDecode') {
    $inf = Inflate $data
    if ($null -eq $inf) { return $null }
    return $ascii.GetString($inf)
  }
  return $ascii.GetString($data)
}

function Parse-CMap([string]$t) {
  $map = @{}
  if (-not $t) { return $map }
  foreach ($b in [regex]::Matches($t, 'beginbfchar([\s\S]*?)endbfchar')) {
    foreach ($p in [regex]::Matches($b.Groups[1].Value, '<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')) {
      $code = [Convert]::ToInt32($p.Groups[1].Value, 16)
      $hex = $p.Groups[2].Value
      $u = ''
      for ($i = 0; $i + 3 -lt $hex.Length; $i += 4) {
        $cp = [Convert]::ToInt32($hex.Substring($i, 4), 16)
        if ($cp -gt 0) { $u += [char]$cp }
      }
      if ($u) { $map[$code] = $u }
    }
  }
  foreach ($b in [regex]::Matches($t, 'beginbfrange([\s\S]*?)endbfrange')) {
    foreach ($r in [regex]::Matches($b.Groups[1].Value, '<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')) {
      $lo = [Convert]::ToInt32($r.Groups[1].Value, 16)
      $hi = [Convert]::ToInt32($r.Groups[2].Value, 16)
      $base = [Convert]::ToInt32($r.Groups[3].Value, 16)
      for ($c = $lo; $c -le $hi; $c++) { if ($base + ($c - $lo) -gt 0) { $map[$c] = [char]($base + ($c - $lo)) } }
    }
  }
  return $map
}

function Decode-PdfString([byte[]]$sb, $enc, $cmap) {
  $out = ''
  $i = 0
  while ($i -lt $sb.Length) {
    $b = $sb[$i]
    if ($b -eq 92) {
      $i++
      if ($i -ge $sb.Length) { break }
      $c = $sb[$i]
      if ($c -eq 110) { $out += "`n"; $i++ }
      elseif ($c -eq 114) { $out += "`r"; $i++ }
      elseif ($c -eq 116) { $out += "`t"; $i++ }
      elseif ($c -eq 40) { $out += '('; $i++ }
      elseif ($c -eq 41) { $out += ')'; $i++ }
      elseif ($c -eq 92) { $out += '\'; $i++ }
      elseif ($c -ge 48 -and $c -le 55) {
        $oct = 0; $n = 0
        while ($i -lt $sb.Length -and $n -lt 3 -and $sb[$i] -ge 48 -and $sb[$i] -le 55) { $oct = $oct * 8 + ($sb[$i] - 48); $i++; $n++ }
        $out += [char]$oct
      } else { $i++ }
      continue
    }
    if ($null -ne $cmap -and $cmap.ContainsKey($b)) { $out += $cmap[$b] }
    elseif ($null -ne $enc) { $out += $enc.GetString($sb, $i, 1) }
    else { $out += [char]$b }
    $i++
  }
  return $out
}

# ---- collect pages -------------------------------------------------------
$cp1252 = $null
$macRoman = $null
try { $cp1252 = [System.Text.Encoding]::GetEncoding(1252) } catch { $cp1252 = [System.Text.Encoding]::ASCII }
try { $macRoman = [System.Text.Encoding]::GetEncoding(10000) } catch { $macRoman = [System.Text.Encoding]::ASCII }
$all = New-Object System.Text.StringBuilder

$pages = @()
foreach ($num in $objects.Keys) {
  if ($objects[$num].dict -match '/Type\s*/Page[\s/>]') { $pages += $num }
}
$pages = $pages | Sort-Object

foreach ($pageNum in $pages) {
  try {
    $pdict = $objects[$pageNum].dict
    $fontMap = @{}
    $fm = [regex]::Match($pdict, '/Font\s*<<([\s\S]*?)>>')
    if ($fm.Success) {
      foreach ($fr in [regex]::Matches($fm.Groups[1].Value, '/(\w+)\s+(\d+)\s+\d+\s+R')) {
        $fontMap[$fr.Groups[1].Value] = [int]$fr.Groups[2].Value
      }
    }
    $encByFont = @{}
    foreach ($fname in $fontMap.Keys) {
      $fobj = $fontMap[$fname]
      $fd = ''
      if ($objects.ContainsKey($fobj)) { $fd = $objects[$fobj].dict }
      $encName = 'WinAnsiEncoding'
      $em = [regex]::Match($fd, '/Encoding\s*/(\w+)')
      if ($em.Success) { $encName = $em.Groups[1].Value }
      else {
        $im = [regex]::Match($fd, '/Encoding\s+(\d+)\s+\d+\s+R')
        if ($im.Success -and $objects.ContainsKey([int]$im.Groups[1].Value)) {
          $ed = $objects[[int]$im.Groups[1].Value].dict
          $em2 = [regex]::Match($ed, '/BaseEncoding\s*/(\w+)')
          if ($em2.Success) { $encName = $em2.Groups[1].Value }
        }
      }
      $cmap = @{}
      $tm = [regex]::Match($fd, '/ToUnicode\s+(\d+)\s+\d+\s+R')
      if ($tm.Success) {
        $ct = Get-StreamText ([int]$tm.Groups[1].Value)
        if ($ct) { $cmap = Parse-CMap $ct }
      }
      $encByFont[$fname] = @{ enc = $encName; cmap = $cmap }
    }
    $contents = @()
    $cm = [regex]::Match($pdict, '/Contents\s+(\d+)\s+\d+\s+R')
    if ($cm.Success) { $contents += [int]$cm.Groups[1].Value }
    else {
      $cam = [regex]::Match($pdict, '/Contents\s*\[([\s\S]*?)\]')
      if ($cam.Success) {
        foreach ($cr in [regex]::Matches($cam.Groups[1].Value, '(\d+)\s+\d+\s+R')) { $contents += [int]$cr.Groups[1].Value }
      }
    }
    foreach ($cn in $contents) {
      $ct = Get-StreamText $cn
      if (-not $ct) { continue }
      foreach ($bt in [regex]::Matches($ct, 'BT([\s\S]*?)ET')) {
        $body = $bt.Groups[1].Value
        $outLine = ''
        $curFont = 'F0'
        $tokenPat = [regex]'/(\w+)\s+Tf|\((?:[^()\\]|\\.)*\)\s*Tj|\[([\s\S]*?)\]\s*TJ|T\*|(?:-?[\d.]+)\s+(?:-?[\d.]+)\s+Td|(?:-?[\d.]+)\s+(?:-?[\d.]+)\s+TD|(?:[\d.\s-]+)\s+Tm'
        foreach ($tk in $tokenPat.Matches($body)) {
          if ($tk.Groups[1].Success) { $curFont = $tk.Groups[1].Value; continue }
          if ($tk.Groups[2].Success) {
            $arr = $tk.Groups[2].Value
            foreach ($el in [regex]::Matches($arr, '\((?:[^()\\]|\\.)*\)|<[0-9A-Fa-f]+>|-?[\d.]+')) {
              $v = $el.Value
              if ($v.StartsWith('(')) {
                $raw = $v.Substring(1, $v.Length - 2)
                $sb2 = $ascii.GetBytes($raw)
                $info = $null
                if ($encByFont.ContainsKey($curFont)) { $info = $encByFont[$curFont] }
                if ($null -eq $info) { $info = @{ enc = 'WinAnsiEncoding'; cmap = @{} } }
                $enc = $cp1252
                if ($info.enc -match 'MacRoman') { $enc = $macRoman }
                $outLine += Decode-PdfString $sb2 $enc $info.cmap
              } elseif ($v.StartsWith('<')) {
                $hex = $v.Substring(1, $v.Length - 2)
                $raw = New-Object byte[] ($hex.Length / 2)
                for ($i = 0; $i -lt $raw.Length; $i++) { $raw[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16) }
                $info = $null
                if ($encByFont.ContainsKey($curFont)) { $info = $encByFont[$curFont] }
                if ($null -eq $info) { $info = @{ enc = 'WinAnsiEncoding'; cmap = @{} } }
                $enc = $cp1252
                if ($info.enc -match 'MacRoman') { $enc = $macRoman }
                $outLine += Decode-PdfString $raw $enc $info.cmap
              } else {
                $adj = [double]$v
                if ($adj -lt -80) { $outLine += ' ' }
              }
            }
            continue
          }
          $t = $tk.Value.TrimEnd()
          if ($t -eq 'T*') { $outLine += "`n" }
          elseif ($t -match 'Td$|TD$|Tm$') { $outLine += "`n" }
        }
        if ($outLine.Trim()) { [void]$all.AppendLine($outLine.Trim()) }
      }
    }
  } catch {
    # skip a broken page; keep going
  }
}

$result = $all.ToString()
if ($Out) {
  [System.IO.File]::WriteAllText($Out, $result, (New-Object System.Text.UTF8Encoding($false)))
  Write-Output "OK extracted $($result.Length) chars -> $Out"
} else {
  Write-Output "=== extracted $($result.Length) chars ==="
  if ($result.Length -gt 0) { Write-Output $result.Substring(0, [Math]::Min(6000, $result.Length)) }
}
