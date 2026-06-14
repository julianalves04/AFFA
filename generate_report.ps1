# generate_report.ps1 - AFFA Report Generator
# Este script lee los datos locales sincronizados y genera un reporte formateado.
# Permite elegir una semana específica y enviar el reporte a Discord.

param (
    [int]$Week = 0, # 0 para autodetectar la última semana disponible en el historial
    [string]$DiscordWebhookUrl = "" # Opcional: URL del webhook de Discord para enviar el reporte
)

# Habilitar codificación UTF-8 para consola
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "         AFFA - GENERADOR DE REPORTES" -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Cyan

# Rutas de archivos
$configPath = Join-Path $PSScriptRoot "data_prueba/config.json"
$standingsPath = Join-Path $PSScriptRoot "data_prueba/standings.json"
$annualPath = Join-Path $PSScriptRoot "data_prueba/annual_results.json"

# Autodetectar la última semana si $Week es 0 o null
$historyDir = Join-Path $PSScriptRoot "data_prueba/history"
if ($Week -eq 0 -or $null -eq $Week) {
    if (Test-Path $historyDir) {
        $files = Get-ChildItem -Path $historyDir -Filter "week_*.json" | Sort-Object Name -Descending
        if ($files.Count -gt 0) {
            $latestFile = $files[0].BaseName
            if ($latestFile -match "week_(\d+)") {
                $Week = [int]$Matches[1]
                Write-Host "Detectada automaticamente la ultima semana: Semana $Week" -ForegroundColor Gray
            }
        }
    }
}
if ($Week -eq 0 -or $null -eq $Week) {
    $Week = 14 # Fallback
}

$weekStr = $Week.ToString("00")
$weekPath = Join-Path $historyDir "week_$weekStr.json"

# Validar existencia de datos locales
if (-not (Test-Path $configPath) -or -not (Test-Path $standingsPath)) {
    Write-Error "No se encontraron las tablas de posiciones sincronizadas. Por favor, corre sync_leagues.ps1 primero."
    Exit
}

if (-not (Test-Path $weekPath)) {
    Write-Error "No se encontro el historial de la semana $Week en: $weekPath"
    Exit
}

# Cargar Datos
$config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
$standings = Get-Content -Raw -Path $standingsPath | ConvertFrom-Json
$weekData = Get-Content -Raw -Path $weekPath | ConvertFrom-Json
$promotedCount = $config.promoted_count

$annualData = $null
if (Test-Path $annualPath) {
    $annualData = Get-Content -Raw -Path $annualPath | ConvertFrom-Json
}

# Definir variables de emojis programaticamente para evitar errores de encoding en la consola
$emojiFootball = "$([char]0xd83c)$([char]0xdfc8)"
$emojiTrophy = "$([char]0xd83c)$([char]0xdfc6)"
$emojiCalendar = "$([char]0xd83d)$([char]0xdcc5)"
$emojiMedal1 = "$([char]0xd83e)$([char]0xdd47)"
$emojiMedal2 = "$([char]0xd83e)$([char]0xdd48)"
$emojiMedal3 = "$([char]0xd83e)$([char]0xdd49)"
$emojiGreenCircle = "$([char]0xd83d)$([char]0xdfe2)"
$emojiRedCircle = "$([char]0xd83d)$([char]0xdd34)"
$emojiDiamondBlue = "$([char]0xd83d)$([char]0xdc99)"
$emojiDiamondOrange = "$([char]0xd83d)$([char]0xdfe1)"
$emojiPin = "$([char]0xd83d)$([char]0xdccc)"
$emojiChart = "$([char]0xd83d)$([char]0xdcc8)"
$emojiController = "$([char]0xd83c)$([char]0xdfae)"
$emojiRocket = "$([char]0xd83d)$([char]0xde80)"
$emojiVS = "VS"

# Construir Reporte Markdown
$report = "$emojiFootball **REPORTE OFICIAL AFFA - SEMANA $Week** $emojiFootball`r`n`r`n"

# A. Resultados de los Matches de la semana
$report += "$emojiController **RESULTADOS DE LA SEMANA - ZONA A**`r`n"
foreach ($m in $weekData.matchups_zona_a) {
    $winnerName = if ($m.team_1.is_winner) { $m.team_1.display_name } else { $m.team_2.display_name }
    $report += "  * **$($m.team_1.display_name)** ($($m.team_1.points.ToString('F2'))) $emojiVS **$($m.team_2.display_name)** ($($m.team_2.points.ToString('F2'))) -> Ganador: **$winnerName**`r`n"
}

$report += "`r`n$emojiController **RESULTADOS DE LA SEMANA - ZONA B**`r`n"
foreach ($m in $weekData.matchups_zona_b) {
    $winnerName = if ($m.team_1.is_winner) { $m.team_1.display_name } else { $m.team_2.display_name }
    $report += "  * **$($m.team_1.display_name)** ($($m.team_1.points.ToString('F2'))) $emojiVS **$($m.team_2.display_name)** ($($m.team_2.points.ToString('F2'))) -> Ganador: **$winnerName**`r`n"
}

# B. Tabla Acumulada
$report += "`r`n$emojiChart **TABLA ACUMULADA (SEMANA $Week)**`r`n`r`n"

$report += "$emojiTrophy **ZONA A**`r`n"
foreach ($t in $standings.zona_a) {
    $medal = "$($t.pos). "
    if ($t.pos -eq 1) { $medal = "$emojiMedal1 " }
    elseif ($t.pos -eq 2) { $medal = "$emojiMedal2 " }
    elseif ($t.pos -eq 3) { $medal = "$emojiMedal3 " }
    
    $indicator = "$emojiRedCircle [Segunda]"
    if ($t.pos -le $promotedCount) { $indicator = "$emojiGreenCircle [Primera]" }
    
    $record = "$($t.wins)-$($t.losses)"
    if ($t.ties -gt 0) { $record += "-$($t.ties)" }
    
    # Concatenar display_name con arroba de forma segura sin interpolar @$
    $dispName = $t.display_name
    $report += "$medal**$($t.team_name)** (@$dispName) | Record: $record | PF: $($t.points_for.ToString('F2')) $indicator`r`n"
}

$report += "`r`n$emojiTrophy **ZONA B**`r`n"
foreach ($t in $standings.zona_b) {
    $medal = "$($t.pos). "
    if ($t.pos -eq 1) { $medal = "$emojiMedal1 " }
    elseif ($t.pos -eq 2) { $medal = "$emojiMedal2 " }
    elseif ($t.pos -eq 3) { $medal = "$emojiMedal3 " }
    
    $indicator = "$emojiRedCircle [Segunda]"
    if ($t.pos -le $promotedCount) { $indicator = "$emojiGreenCircle [Primera]" }
    
    $record = "$($t.wins)-$($t.losses)"
    if ($t.ties -gt 0) { $record += "-$($t.ties)" }
    
    $dispName = $t.display_name
    $report += "$medal**$($t.team_name)** (@$dispName) | Record: $record | PF: $($t.points_for.ToString('F2')) $indicator`r`n"
}

# C. Proyecciones de Playoffs
$report += "`r`n$emojiRocket **PROYECCION DE PLAYOFFS (Semanas 15 a 17)**`r`n"
$report += "Cruces proyectados en base a las posiciones actuales:`r`n`r`n"

if ($standings.playoffs_proyectados) {
    # Zona A
    $playoffsA = $standings.playoffs_proyectados.zona_a
    $semisA = $playoffsA.semis_directas | ForEach-Object { "@" + $_.display_name + " (Seed " + $_.seed + ")" }
    $semisAList = $semisA -join " y "
    
    $report += "$emojiDiamondBlue **ZONA A:**`r`n"
    $report += "  * Semifinalistas directos: $semisAList`r`n"
    $report += "  * Cuartos de Final (Semana 15):`r`n"
    foreach ($c in $playoffsA.cuartos) {
        $report += "    - Match $($c.match_id): (Seed $($c.seed_1)) **@$($c.team_1)** VS (Seed $($c.seed_2)) **@$($c.team_2)**`r`n"
    }
    
    # Zona B
    $playoffsB = $standings.playoffs_proyectados.zona_b
    $semisB = $playoffsB.semis_directas | ForEach-Object { "@" + $_.display_name + " (Seed " + $_.seed + ")" }
    $semisBList = $semisB -join " y "
    
    $report += "`r`n$emojiDiamondOrange **ZONA B:**`r`n"
    $report += "  * Semifinalistas directos: $semisBList`r`n"
    $report += "  * Cuartos de Final (Semana 15):`r`n"
    foreach ($c in $playoffsB.cuartos) {
        $report += "    - Match $($c.match_id): (Seed $($c.seed_1)) **@$($c.team_1)** VS (Seed $($c.seed_2)) **@$($c.team_2)**`r`n"
    }
} else {
    $report += "  * No hay suficientes equipos para proyectar playoffs.`r`n"
}

# D. Historial de Campeones Anuales
if ($annualData) {
    $report += "`r`n$emojiTrophy **HISTORIAL DE CAMPEONES DE PLAYOFFS**`r`n"
    foreach ($temp in $annualData.temporadas) {
        $report += "  * **Temporada $($temp.anio)**: Campeon Zona A: **$($temp.campeon_zona_a)** | Campeon Zona B: **$($temp.campeon_zona_b)**`r`n"
    }
}

# Mostrar en consola
Write-Host "`nReporte Generado con Exito para la Semana $($Week):`n" -ForegroundColor Green
Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray
Write-Host $report
Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray

# Guardar localmente
$reportFileName = "week_" + $weekStr + "_report.txt"
$reportPath = Join-Path $PSScriptRoot "data_prueba/history/$reportFileName"
$report | Out-File -FilePath $reportPath -Encoding utf8
Write-Host "Reporte guardado localmente en: $reportPath" -ForegroundColor Green

# Enviar a Discord
if ($DiscordWebhookUrl -and $DiscordWebhookUrl.StartsWith("http")) {
    Write-Host "Enviando reporte a Discord..." -ForegroundColor Gray
    try {
        $body = @{ content = $report } | ConvertTo-Json -Depth 4
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $response = Invoke-RestMethod -Uri $DiscordWebhookUrl -Method Post -Body $bodyBytes -ContentType "application/json; charset=utf-8"
        Write-Host "Reporte enviado a Discord con exito!" -ForegroundColor Green
    } catch {
        Write-Error "No se pudo enviar el reporte a Discord: $_"
    }
}
