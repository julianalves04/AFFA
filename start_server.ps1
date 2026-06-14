# start_server.ps1 - AFFA Static Web Server
# Este script inicia un servidor web ligero nativo de PowerShell en http://localhost:8080/
# Permite ver la interfaz web de AFFA y cargar los datos JSON locales sin errores de CORS.

param (
    [int]$Port = 8080
)

# Habilitar soporte UTF-8
$OutputEncoding = [System.Text.Encoding]::UTF8

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")

try {
    $listener.Start()
} catch {
    Write-Host "Error al iniciar el servidor en el puerto $Port : $_" -ForegroundColor Red
    Write-Host "Es posible que otro servidor ya este usando este puerto." -ForegroundColor Yellow
    Exit
}

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "         AFFA - SERVIDOR WEB LOCAL" -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "Servidor activo en: http://localhost:$Port/" -ForegroundColor Green
Write-Host "Abre tu navegador e ingresa a la direccion anterior." -ForegroundColor Gray
Write-Host "Presiona [CTRL + C] en esta consola para detener el servidor." -ForegroundColor Yellow
Write-Host "---------------------------------------------" -ForegroundColor DarkGray

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        
        # Obtener la ruta relativa del archivo solicitado
        $urlPath = $request.Url.LocalPath.TrimStart('/')
        if ($urlPath -eq "") {
            $urlPath = "index.html"
        }
        
        $filePath = Join-Path $PSScriptRoot $urlPath
        
        # Validar que el archivo exista y este dentro del directorio del proyecto
        if (Test-Path $filePath -PathType Leaf) {
            # Determinar MIME Type
            $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
            $contentType = "text/plain; charset=utf-8"
            switch ($ext) {
                ".html" { $contentType = "text/html; charset=utf-8" }
                ".css"  { $contentType = "text/css; charset=utf-8" }
                ".js"   { $contentType = "application/javascript; charset=utf-8" }
                ".json" { $contentType = "application/json; charset=utf-8" }
                ".png"  { $contentType = "image/png" }
                ".jpg"  { $contentType = "image/jpeg" }
                ".ico"  { $contentType = "image/x-icon" }
            }
            
            # Leer bytes y escribir respuesta
            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            $response.ContentType = $contentType
            $response.ContentLength64 = $bytes.Length
            $response.Headers.Add("Access-Control-Allow-Origin", "*")
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            # Archivo no encontrado (404)
            $response.StatusCode = 404
            $response.ContentType = "text/plain; charset=utf-8"
            $bytes = [System.Text.Encoding]::UTF8.GetBytes("404 - Archivo no encontrado")
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        }
    } catch {
        # Ignorar errores de conexion truncada o cierres rapidos de pestanas
    } finally {
        if ($response) {
            try { $response.Close() } catch {}
        }
    }
}
