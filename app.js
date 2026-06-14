// app.js - AFFA static query dashboard logic

// State
let state = {
    config: null,
    standings: null,
    annualResults: null,
    currentWeek: 14
};

// DOM Elements
const syncDot = document.getElementById('sync-dot');
const syncText = document.getElementById('sync-text');
const tbodyZonaA = document.getElementById('tbody-zona-a');
const tbodyZonaB = document.getElementById('tbody-zona-b');
const tbodyChampions = document.getElementById('tbody-champions');
const weekSelect = document.getElementById('week-select');
const matchupsZonaA = document.getElementById('matchups-zona-a');
const matchupsZonaB = document.getElementById('matchups-zona-b');

// Initialize
document.addEventListener('DOMContentLoaded', async () => {
    setupTabSwitching();
    setupBracketSwitching();
    
    // Load config first, then data
    try {
        await loadConfigAndData();
        setupWeekSelector();
        updateUI();
        loadWeekMatchups(state.currentWeek);
    } catch (e) {
        console.error("Error loading local AFFA database:", e);
        showConnectionError(e);
    }
});

// Setup tab navigation
function setupTabSwitching() {
    const tabBtns = document.querySelectorAll('.tabs-nav .tab-btn');
    const tabContents = document.querySelectorAll('.tab-content');
    
    tabBtns.forEach(btn => {
        btn.addEventListener('click', () => {
            const targetTab = btn.getAttribute('data-tab');
            if (!targetTab) return;
            
            tabBtns.forEach(b => b.classList.remove('active'));
            tabContents.forEach(c => c.classList.remove('active'));
            
            btn.classList.add('active');
            const targetEl = document.getElementById(targetTab);
            if (targetEl) {
                targetEl.classList.add('active');
            }
        });
    });
}

// Setup bracket division switching for Playoffs tab
function setupBracketSwitching() {
    const btnA = document.getElementById('btn-bracket-a');
    const btnB = document.getElementById('btn-bracket-b');
    const bracketA = document.getElementById('bracket-a');
    const bracketB = document.getElementById('bracket-b');
    
    if (btnA && btnB && bracketA && bracketB) {
        btnA.addEventListener('click', () => {
            btnA.classList.add('active');
            btnB.classList.remove('active');
            bracketA.style.display = 'flex';
            bracketB.style.display = 'none';
        });
        btnB.addEventListener('click', () => {
            btnB.classList.add('active');
            btnA.classList.remove('active');
            bracketB.style.display = 'flex';
            bracketA.style.display = 'none';
        });
    }
}

// Load configurations and general standings data
async function loadConfigAndData() {
    // 1. Config
    const resConfig = await fetch('data_prueba/config.json');
    if (!resConfig.ok) throw new Error("No se pudo leer data_prueba/config.json");
    state.config = await resConfig.json();
    
    // 2. Standings
    const resStandings = await fetch('data_prueba/standings.json');
    if (!resStandings.ok) throw new Error("No se pudo leer data_prueba/standings.json");
    state.standings = await resStandings.json();
    
    // 3. Annual results (optional)
    try {
        const resAnnual = await fetch('data_prueba/annual_results.json');
        if (resAnnual.ok) {
            state.annualResults = await resAnnual.json();
        }
    } catch (err) {
        console.log("No annual results found or failed to load. Skipping.");
    }
}

// Setup week select listener
function setupWeekSelector() {
    weekSelect.value = state.currentWeek.toString();
    weekSelect.addEventListener('change', (e) => {
        state.currentWeek = parseInt(e.target.value);
        loadWeekMatchups(state.currentWeek);
    });
}

// Load weekly matchups from history files
async function loadWeekMatchups(week) {
    const paddedWeek = week.toString().padStart(2, '0');
    matchupsZonaA.innerHTML = '<div style="color: var(--text-secondary);">Cargando matchups...</div>';
    matchupsZonaB.innerHTML = '<div style="color: var(--text-secondary);">Cargando matchups...</div>';
    
    try {
        const resMatchups = await fetch(`data_prueba/history/week_${paddedWeek}.json`);
        if (!resMatchups.ok) throw new Error(`No se pudo leer el historial de la semana ${week}`);
        const data = await resMatchups.json();
        
        renderWeekMatchups('zona-a', data.matchups_zona_a, matchupsZonaA);
        renderWeekMatchups('zona-b', data.matchups_zona_b, matchupsZonaB);
    } catch (err) {
        console.error(err);
        matchupsZonaA.innerHTML = `<div style="color: var(--color-danger); font-size: 0.9rem;">Error al cargar semana ${week}.</div>`;
        matchupsZonaB.innerHTML = `<div style="color: var(--color-danger); font-size: 0.9rem;">Error al cargar semana ${week}.</div>`;
    }
}

// Update primary tables
function updateUI() {
    // Status
    syncDot.className = "sync-dot success";
    syncText.innerText = `Base de datos local: Activa (Último sync: ${state.standings.last_updated})`;
    
    // Render Standings
    renderStandingsTable(state.standings.zona_a, tbodyZonaA);
    renderStandingsTable(state.standings.zona_b, tbodyZonaB);
    
    // Render Projections
    renderProjections();
    
    // Render Champions
    renderChampions();
}

// Render Standings
function renderStandingsTable(teamsData, tbodyElement) {
    tbodyElement.innerHTML = '';
    const limit = state.config.promoted_count;
    
    teamsData.forEach((team) => {
        const tr = document.createElement('tr');
        
        // Highlight zones
        if (team.pos <= limit) {
            tr.className = "promo-zone";
        } else {
            tr.className = "releg-zone";
        }
        
        const record = `${team.wins}-${team.losses}${team.ties > 0 ? `-${team.ties}` : ''}`;
        
        tr.innerHTML = `
            <td><div class="pos-num">${team.pos}</div></td>
            <td>
                <div>
                    <div class="team-name">${escapeHtml(team.team_name)}</div>
                    <div class="manager-name">@${escapeHtml(team.display_name)}</div>
                </div>
            </td>
            <td style="text-align: center; font-weight: 500;">${record}</td>
            <td style="text-align: right; font-weight: 600; font-variant-numeric: tabular-nums;">${team.points_for.toFixed(2)}</td>
            <td style="text-align: right; color: var(--text-muted); font-size: 0.85rem; font-variant-numeric: tabular-nums;">${team.points_against.toFixed(2)}</td>
        `;
        tbodyElement.appendChild(tr);
    });
}

// Render weekly matchups
function renderWeekMatchups(zoneKey, matchups, containerElement) {
    containerElement.innerHTML = '';
    
    if (!matchups || matchups.length === 0) {
        containerElement.innerHTML = '<div style="color: var(--text-secondary);">No hay partidos registrados.</div>';
        return;
    }
    
    matchups.forEach((m) => {
        const div = document.createElement('div');
        
        let winnerClass = '';
        if (m.team_1.is_winner) {
            winnerClass = 'winner-1';
        } else if (m.team_2.is_winner) {
            winnerClass = 'winner-2';
        }
        
        div.className = `matchup-item ${winnerClass}`;
        
        div.innerHTML = `
            <div class="matchup-team team-1">
                <span class="matchup-team-name">${escapeHtml(m.team_1.display_name)}</span>
                <span class="matchup-points">${m.team_1.points.toFixed(2)}</span>
            </div>
            <div class="matchup-vs">VS</div>
            <div class="matchup-team team-2">
                <span class="matchup-team-name">${escapeHtml(m.team_2.display_name)}</span>
                <span class="matchup-points">${m.team_2.points.toFixed(2)}</span>
            </div>
        `;
        
        containerElement.appendChild(div);
    });
}

// Render Projections (Playoff Brackets)
function renderProjections() {
    if (!state.standings || !state.standings.playoffs_proyectados) return;
    
    populateBracket('zona_a');
    populateBracket('zona_b');
}

// Helper to populate a bracket for a specific zone
function populateBracket(zoneKey) {
    const suffix = zoneKey === 'zona_a' ? '-a' : '-b';
    const data = state.standings.playoffs_proyectados[zoneKey];
    
    if (!data) return;
    
    const zoneTag = zoneKey === 'zona_a' ? ' (Z-A)' : ' (Z-B)';
    
    // 1. Cuartos de Final (QF1: Seed 3 vs Seed 6, QF2: Seed 4 vs Seed 5)
    const qf1 = document.getElementById(`qf1${suffix}`);
    const qf2 = document.getElementById(`qf2${suffix}`);
    
    const matchA = data.cuartos.find(m => m.match_id === 'A');
    const matchB = data.cuartos.find(m => m.match_id === 'B');
    
    if (qf1 && matchA) {
        const team1 = (matchA.team_name_1 || matchA.team_1) + zoneTag;
        const team2 = (matchA.team_name_2 || matchA.team_2) + zoneTag;
        qf1.innerHTML = `
            <div class="bracket-team-row">
                <div>
                    <span class="bracket-seed">#${matchA.seed_1}</span>
                    <span class="bracket-team-name" title="${escapeHtml(team1)}">${escapeHtml(team1)}</span>
                </div>
                <span class="bracket-team-score">-</span>
            </div>
            <div class="bracket-team-row">
                <div>
                    <span class="bracket-seed">#${matchA.seed_2}</span>
                    <span class="bracket-team-name" title="${escapeHtml(team2)}">${escapeHtml(team2)}</span>
                </div>
                <span class="bracket-team-score">-</span>
            </div>
        `;
    }
    
    if (qf2 && matchB) {
        const team1 = (matchB.team_name_1 || matchB.team_1) + zoneTag;
        const team2 = (matchB.team_name_2 || matchB.team_2) + zoneTag;
        qf2.innerHTML = `
            <div class="bracket-team-row">
                <div>
                    <span class="bracket-seed">#${matchB.seed_1}</span>
                    <span class="bracket-team-name" title="${escapeHtml(team1)}">${escapeHtml(team1)}</span>
                </div>
                <span class="bracket-team-score">-</span>
            </div>
            <div class="bracket-team-row">
                <div>
                    <span class="bracket-seed">#${matchB.seed_2}</span>
                    <span class="bracket-team-name" title="${escapeHtml(team2)}">${escapeHtml(team2)}</span>
                </div>
                <span class="bracket-team-score">-</span>
            </div>
        `;
    }
    
    // 2. Semifinales (SF1: Seed 1 vs Winner Match B, SF2: Seed 2 vs Winner Match A)
    const sf1 = document.getElementById(`sf1${suffix}`);
    const sf2 = document.getElementById(`sf2${suffix}`);
    
    const seed1 = data.semis_directas.find(s => s.seed === 1);
    const seed2 = data.semis_directas.find(s => s.seed === 2);
    
    if (sf1 && seed1) {
        const team1 = (seed1.team_name || seed1.display_name) + zoneTag;
        sf1.innerHTML = `
            <div class="bracket-team-row">
                <div>
                    <span class="bracket-seed">#1</span>
                    <span class="bracket-team-name" title="${escapeHtml(team1)}">${escapeHtml(team1)}</span>
                </div>
                <span class="bracket-team-score">-</span>
            </div>
            <div class="bracket-team-row">
                <div>
                    <span class="bracket-seed">QF</span>
                    <span class="bracket-team-name" style="font-style: italic; color: var(--text-muted);">Ganador QF B (#4 vs #5)</span>
                </div>
                <span class="bracket-team-score">-</span>
            </div>
        `;
    }
    
    if (sf2 && seed2) {
        const team2 = (seed2.team_name || seed2.display_name) + zoneTag;
        sf2.innerHTML = `
            <div class="bracket-team-row">
                <div>
                    <span class="bracket-seed">#2</span>
                    <span class="bracket-team-name" title="${escapeHtml(team2)}">${escapeHtml(team2)}</span>
                </div>
                <span class="bracket-team-score">-</span>
            </div>
            <div class="bracket-team-row">
                <div>
                    <span class="bracket-seed">QF</span>
                    <span class="bracket-team-name" style="font-style: italic; color: var(--text-muted);">Ganador QF A (#3 vs #6)</span>
                </div>
                <span class="bracket-team-score">-</span>
            </div>
        `;
    }
    
    // 3. Final (Winner SF1 vs Winner SF2)
    const final = document.getElementById(`final${suffix}`);
    if (final) {
        final.innerHTML = `
            <div class="bracket-team-row">
                <div>
                    <span class="bracket-seed">SF</span>
                    <span class="bracket-team-name" style="font-style: italic; color: var(--text-muted);">Ganador Semifinal 1</span>
                </div>
                <span class="bracket-team-score">-</span>
            </div>
            <div class="bracket-team-row">
                <div>
                    <span class="bracket-seed">SF</span>
                    <span class="bracket-team-name" style="font-style: italic; color: var(--text-muted);">Ganador Semifinal 2</span>
                </div>
                <span class="bracket-team-score">-</span>
            </div>
        `;
    }
}

// Render Champions
function renderChampions() {
    tbodyChampions.innerHTML = '';
    
    if (!state.annualResults || !state.annualResults.temporadas || state.annualResults.temporadas.length === 0) {
        tbodyChampions.innerHTML = '<tr><td colspan="3" style="text-align: center; color: var(--text-secondary);">No hay temporadas registradas aún.</td></tr>';
        return;
    }
    
    state.annualResults.temporadas.forEach(temp => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
            <td style="font-weight: 700; color: var(--color-arg-blue);">${temp.anio}</td>
            <td style="font-weight: 600;">👑 ${escapeHtml(temp.campeon_zona_a)}</td>
            <td style="font-weight: 600;">👑 ${escapeHtml(temp.campeon_zona_b)}</td>
        `;
        tbodyChampions.appendChild(tr);
    });
}

// Show CORS/connection errors
function showConnectionError(error) {
    syncDot.className = "sync-dot error";
    syncText.innerText = "Error al conectar con la base de datos local";
    
    const errorMsg = `
        <div class="alert alert-info" style="grid-column: 1 / -1; background: rgba(244, 63, 94, 0.08); border-left: 4px solid var(--color-danger); color: var(--text-primary);">
            <span class="alert-icon">⚠️</span>
            <div>
                <strong>Error de conexión local (CORS o archivos faltantes):</strong> 
                <p style="margin-top: 0.25rem; font-size: 0.85rem; color: var(--text-secondary);">
                    Los navegadores modernos bloquean peticiones HTTP a archivos locales (file://) por motivos de seguridad.
                </p>
                <p style="margin-top: 0.5rem; font-weight: 600;">
                    Para solucionar esto, por favor ejecuta el servidor local de prueba corriendo en tu consola de PowerShell:
                </p>
                <code style="display: block; background: #000; padding: 0.5rem; margin-top: 0.25rem; border-radius: 4px; font-family: monospace; font-size: 0.85rem;">
                    powershell -ExecutionPolicy Bypass -File .\\start_server.ps1
                </code>
                <p style="margin-top: 0.5rem;">
                    Y luego abre el sitio en la siguiente dirección: <a href="http://localhost:8080" style="color: var(--color-arg-blue); text-decoration: underline; font-weight: 700;">http://localhost:8080</a>
                </p>
            </div>
        </div>
    `;
    
    tbodyZonaA.innerHTML = '<tr><td colspan="5" style="text-align: center; color: var(--color-danger);">Error al cargar.</td></tr>';
    tbodyZonaB.innerHTML = '<tr><td colspan="5" style="text-align: center; color: var(--color-danger);">Error al cargar.</td></tr>';
    tbodyChampions.innerHTML = '<tr><td colspan="3" style="text-align: center; color: var(--color-danger);">Error al cargar.</td></tr>';
    
    // Append the alert before the standings tables
    document.querySelector('.grid-2').insertAdjacentHTML('beforebegin', errorMsg);
}

// Utility to escape HTML and prevent injections
function escapeHtml(str) {
    if (typeof str !== 'string') return '';
    return str
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}
