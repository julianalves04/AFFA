# sync_leagues.ps1 - AFFA Sleeper Sync Tool
# Este script descarga los datos de las ligas configuradas, calcula posiciones y genera el historial.

# Habilitar codificación UTF-8 para salida en consola
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "         AFFA - SLEEPER SYNC TOOL" -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Cyan

# 1. Cargar Configuración
$configPath = Join-Path $PSScriptRoot "data_prueba/config.json"
if (-not (Test-Path $configPath)) {
    Write-Error "No se encontro el archivo de configuracion en: $configPath"
    Exit
}

$config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
$leagueAId = $config.league_a_id
$leagueBId = $config.league_b_id
$promotedCount = $config.promoted_count

Write-Host "Ligas a procesar:" -ForegroundColor Gray
Write-Host "  Zona A: $leagueAId" -ForegroundColor Gray
Write-Host "  Zona B: $leagueBId" -ForegroundColor Gray
Write-Host "  Limite de Ascensos: $promotedCount" -ForegroundColor Gray

# Crear directorios si no existen
$historyDir = Join-Path $PSScriptRoot "data_prueba/history"
if (-not (Test-Path $historyDir)) {
    New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
}

# Función para obtener y procesar datos de una liga
function Get-ProcessedLeagueData($leagueId) {
    Write-Host "Sincronizando Liga ID: $leagueId..." -ForegroundColor Gray
    try {
        # A. Metadata de Liga
        $league = Invoke-RestMethod -Uri "https://api.sleeper.app/v1/league/$leagueId" -ErrorAction Stop
        
        # B. Usuarios
        $users = Invoke-RestMethod -Uri "https://api.sleeper.app/v1/league/$leagueId/users" -ErrorAction Stop
        $userMap = @{}
        foreach ($u in $users) {
            $tName = $u.display_name + "'s Team"
            if ($u.metadata -and $u.metadata.team_name) {
                $tName = $u.metadata.team_name
            }
            $userMap[$u.user_id] = @{
                DisplayName = $u.display_name
                TeamName = $tName
            }
        }
        
        # C. Rosters
        $rosters = Invoke-RestMethod -Uri "https://api.sleeper.app/v1/league/$leagueId/rosters" -ErrorAction Stop
        $standings = @()
        $rosterMap = @{} # Para buscar rapidamente por roster_id
        
        foreach ($r in $rosters) {
            $owner = $userMap[$r.owner_id]
            if (-not $owner) {
                $owner = @{
                    DisplayName = "Invitado"
                    TeamName = "Roster " + $r.roster_id
                }
            }
            
            # Puntos a favor
            $fpts = if ($r.settings.fpts) { $r.settings.fpts } else { 0 }
            $fptsDec = if ($r.settings.fpts_decimal) { $r.settings.fpts_decimal } else { 0 }
            $pointsFor = [double]("$fpts.$fptsDec")
            
            # Puntos en contra
            $fptsAgainst = if ($r.settings.fpts_against) { $r.settings.fpts_against } else { 0 }
            $fptsAgainstDec = if ($r.settings.fpts_against_decimal) { $r.settings.fpts_against_decimal } else { 0 }
            $pointsAgainst = [double]("$fptsAgainst.$fptsAgainstDec")
            
            $teamObj = @{
                roster_id = $r.roster_id
                display_name = $owner.DisplayName
                team_name = $owner.TeamName
                wins = $r.settings.wins
                losses = $r.settings.losses
                ties = $r.settings.ties
                points_for = $pointsFor
                points_against = $pointsAgainst
            }
            
            $standings += $teamObj
            $rosterMap[$r.roster_id] = @{
                DisplayName = $owner.DisplayName
                TeamName = $owner.TeamName
            }
        }
        
        # Ordenar tabla
        # Récord (Victorias) DESC -> Puntos a Favor DESC -> Puntos en Contra ASC
        $sortedStandings = $standings | Sort-Object -Property @{Expression={$_.wins}; Descending=$true}, @{Expression={$_.points_for}; Descending=$true}, @{Expression={$_.points_against}; Ascending=$true}
        
        # Asignar posiciones 1-indexadas
        $pos = 1
        $finalStandings = @()
        foreach ($team in $sortedStandings) {
            $teamWithPos = [ordered]@{
                pos = $pos
                roster_id = $team.roster_id
                display_name = $team.display_name
                team_name = $team.team_name
                wins = $team.wins
                losses = $team.losses
                ties = $team.ties
                points_for = $team.points_for
                points_against = $team.points_against
            }
            $finalStandings += [PSCustomObject]$teamWithPos
            $pos++
        }
        
        # Identificar Campeón de Playoffs
        # Sleeper guarda el ID del ganador en metadata.latest_league_winner_roster_id
        $winnerRosterId = $league.metadata.latest_league_winner_roster_id
        $championName = "Sin Definir"
        if ($winnerRosterId) {
            $winnerIdInt = [int]$winnerRosterId
            if ($rosterMap[$winnerIdInt]) {
                $championName = $rosterMap[$winnerIdInt].DisplayName
            }
        }
        
        return @{
            Name = $league.name
            Season = $league.season
            LastScoredLeg = $league.settings.last_scored_leg
            Standings = $finalStandings
            RosterMap = $rosterMap
            Champion = $championName
        }
    } catch {
        Write-Error "Error procesando liga $leagueId : $_"
        return $null
    }
}

# Helper para proyectar bracket de playoffs (Seeds 1-6)
function Get-ProjectedPlayoffs($standings) {
    if ($standings.Count -lt 6) { return $null }
    
    $seed1 = $standings[0]
    $seed2 = $standings[1]
    $seed3 = $standings[2]
    $seed4 = $standings[3]
    $seed5 = $standings[4]
    $seed6 = $standings[5]
    
    return [ordered]@{
        semis_directas = @(
            [ordered]@{ seed = 1; display_name = $seed1.display_name; team_name = $seed1.team_name; roster_id = $seed1.roster_id }
            [ordered]@{ seed = 2; display_name = $seed2.display_name; team_name = $seed2.team_name; roster_id = $seed2.roster_id }
        )
        cuartos = @(
            [ordered]@{ 
                match_id = "A"
                team_1 = $seed3.display_name
                team_name_1 = $seed3.team_name
                roster_id_1 = $seed3.roster_id
                seed_1 = 3
                team_2 = $seed6.display_name
                team_name_2 = $seed6.team_name
                roster_id_2 = $seed6.roster_id
                seed_2 = 6
            }
            [ordered]@{ 
                match_id = "B"
                team_1 = $seed4.display_name
                team_name_1 = $seed4.team_name
                roster_id_1 = $seed4.roster_id
                seed_1 = 4
                team_2 = $seed5.display_name
                team_name_2 = $seed5.team_name
                roster_id_2 = $seed5.roster_id
                seed_2 = 5
            }
        )
    }
}

# Ejecutar extracciones de ambas zonas
$dataA = Get-ProcessedLeagueData -leagueId $leagueAId
if (-not $dataA) { Exit }

$dataB = Get-ProcessedLeagueData -leagueId $leagueBId
if (-not $dataB) { Exit }

# Calcular playoffs proyectados para ambas zonas
$playoffsA = Get-ProjectedPlayoffs -standings $dataA.Standings
$playoffsB = Get-ProjectedPlayoffs -standings $dataB.Standings

# 2. Generar data_prueba/standings.json
$standingsJson = [ordered]@{
    last_updated = (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz")
    zona_a = $dataA.Standings
    zona_b = $dataB.Standings
    playoffs_proyectados = [ordered]@{
        zona_a = $playoffsA
        zona_b = $playoffsB
    }
}

$standingsJson | ConvertTo-Json -Depth 5 | Out-File -FilePath (Join-Path $PSScriptRoot "data_prueba/standings.json") -Encoding utf8
Write-Host "Tabla de posiciones guardada en: data_prueba/standings.json" -ForegroundColor Green

# 3. Generar data_prueba/annual_results.json
# Cargar resultados previos si existen
$annualResultsPath = Join-Path $PSScriptRoot "data_prueba/annual_results.json"
$annualResults = @{ temporadas = @() }
if (Test-Path $annualResultsPath) {
    try {
        $annualResults = Get-Content -Raw -Path $annualResultsPath | ConvertFrom-Json
    } catch {
        # ignore and overwrite
    }
}

# Buscar si ya existe la temporada actual en el historial
$currentSeason = $dataA.Season
$seasonEntry = $null
foreach ($temp in $annualResults.temporadas) {
    if ($temp.anio -eq $currentSeason) {
        $seasonEntry = $temp
        break
    }
}

# Crear o actualizar registro anual
$posFinalesA = @()
foreach ($t in $dataA.Standings) {
    $posFinalesA += [ordered]@{ pos = $t.pos; display_name = $t.display_name; team_name = $t.team_name }
}
$posFinalesB = @()
foreach ($t in $dataB.Standings) {
    $posFinalesB += [ordered]@{ pos = $t.pos; display_name = $t.display_name; team_name = $t.team_name }
}

$newSeasonEntry = [ordered]@{
    anio = [int]$currentSeason
    campeon_zona_a = $dataA.Champion
    campeon_zona_b = $dataB.Champion
    posiciones_finales = @{
        zona_a = $posFinalesA
        zona_b = $posFinalesB
    }
}

if ($seasonEntry) {
    # Reemplazar existente
    $index = $annualResults.temporadas.IndexOf($seasonEntry)
    $annualResults.temporadas[$index] = $newSeasonEntry
} else {
    # Agregar nuevo
    $annualResults.temporadas += [PSCustomObject]$newSeasonEntry
}

$annualResults | ConvertTo-Json -Depth 6 | Out-File -FilePath $annualResultsPath -Encoding utf8
Write-Host "Historial anual guardado en: data_prueba/annual_results.json" -ForegroundColor Green

# 4. Generar data_prueba/history/week_XX.json (Semanas 1 a 14)
# Para cada semana de la temporada regular, consultamos los enfrentamientos
Write-Host "Sincronizando enfrentamientos semanales (Semanas 1 a 14)..." -ForegroundColor Gray

# Determinar la semana activa para evitar descargar semanas pasadas completadas
$lastScoredWeek = [Math]::Max($dataA.LastScoredLeg, $dataB.LastScoredLeg)
$currentActiveWeek = [Math]::Min(14, $lastScoredWeek + 1)
if ($lastScoredWeek -eq 0) { $currentActiveWeek = 1 }

for ($week = 1; $week -le 14; $week++) {
    $weekFileName = "week_" + $week.ToString("00") + ".json"
    $weekFilePath = Join-Path $historyDir $weekFileName
    
    # Si la semana ya paso y tenemos el archivo guardado, omitimos
    if ((Test-Path $weekFilePath) -and ($week -lt $currentActiveWeek)) {
        Write-Host "  Semana $week ya guardada. Omitiendo..." -ForegroundColor DarkGray
        continue
    }

    Write-Host "  Procesando Semana $week..." -ForegroundColor DarkGray
    
    # Obtener matchups de Zona A
    $matchupsA = Invoke-RestMethod -Uri "https://api.sleeper.app/v1/league/$leagueAId/matchups/$week"
    # Obtener matchups de Zona B
    $matchupsB = Invoke-RestMethod -Uri "https://api.sleeper.app/v1/league/$leagueBId/matchups/$week"
    
    # Función para agrupar matchups por matchup_id
    function Group-Matchups($matchupsRaw, $rosterMap) {
        $groups = @{}
        foreach ($m in $matchupsRaw) {
            $matchId = $m.matchup_id
            if (-not $groups[$matchId]) {
                $groups[$matchId] = @()
            }
            $groups[$matchId] += $m
        }
        
        $matchupsProcessed = @()
        foreach ($mId in $groups.Keys) {
            $teamsInMatch = $groups[$mId]
            if ($teamsInMatch.Count -eq 2) {
                $team1Raw = $teamsInMatch[0]
                $team2Raw = $teamsInMatch[1]
                
                $name1 = $rosterMap[$team1Raw.roster_id].DisplayName
                $name2 = $rosterMap[$team2Raw.roster_id].DisplayName
                
                $p1 = $team1Raw.points
                $p2 = $team2Raw.points
                
                $isWinner1 = $p1 -gt $p2
                $isWinner2 = $p2 -gt $p1
                
                $matchupsProcessed += [ordered]@{
                    matchup_id = $mId
                    team_1 = @{ display_name = $name1; points = $p1; is_winner = $isWinner1 }
                    team_2 = @{ display_name = $name2; points = $p2; is_winner = $isWinner2 }
                }
            }
        }
        return $matchupsProcessed
    }
    
    $processedA = Group-Matchups -matchupsRaw $matchupsA -rosterMap $dataA.RosterMap
    $processedB = Group-Matchups -matchupsRaw $matchupsB -rosterMap $dataB.RosterMap
    
    $weekJson = [ordered]@{
        week = $week
        matchups_zona_a = $processedA
        matchups_zona_b = $processedB
    }
    
    $weekFileName = "week_" + $week.ToString("00") + ".json"
    $weekJson | ConvertTo-Json -Depth 5 | Out-File -FilePath (Join-Path $historyDir $weekFileName) -Encoding utf8
}

Write-Host "Historial semanal guardado con exito!" -ForegroundColor Green
Write-Host "Sincronizacion de datos completada satisfactoriamente." -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
