# quality_test_v2.ps1
# Compara la calidad de codigo entre dos modelos (estandar vs reparado)
# El servidor debe estar corriendo en http://localhost:8080

$prompts = @(
    "Escribe una funcion PHP que valide una direccion de email usando filter_var y tambien una validacion extra (dominio no numerico, longitud maxima 255).",
    "Crea una clase PHP User con propiedades private: id, name, email, password. Incluye constructor, getters/setters, y un metodo validate() que devuelva true si email y password cumplen unos criterios basicos (email valido, password minimo 8 caracteres).",
    "Implementa una funcion recursiva factorial(\$n) en PHP que maneje numeros negativos lanzando una excepcion. Ademas, escribe los test unitarios usando PHPUnit para esta funcion.",
    "Escribe un snippet PHP que conecte a una base de datos MySQL usando PDO, ejecute una consulta SELECT con parametros seguros (prepared statement) y devuelva los resultados como un array asociativo. Incluye manejo de excepciones.",
    "Refactoriza el siguiente codigo PHP para que sea mas legible y use buenas practicas: function do(\$a,\$b){if(\$a>0){return \$a+\$b;}else{return \$a*\$b;}} (nota: 'do' es palabra reservada, cambiale el nombre).",
    "Explica con ejemplos de codigo la diferencia entre include, require, include_once y require_once en PHP. Cuando usar cada uno."
)

$outDir = "C:\llama-benchmark\model_comparison_v2"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$url = "http://localhost:8080/v1/chat/completions"
$healthUrl = "http://localhost:8080/health"

# Función para esperar a que el servidor responda
function Wait-ForServer {
    Write-Host "Verificando que el servidor responde..." -ForegroundColor Yellow
    $maxRetries = 10
    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            $response = Invoke-RestMethod -Uri $healthUrl -Method Get -ErrorAction Stop
            Write-Host "  Servidor listo (status: $($response.status))" -ForegroundColor Green
            return $true
        } catch {
            Write-Host "  Esperando... ($i/$maxRetries)" -ForegroundColor Gray
            Start-Sleep -Seconds 2
        }
    }
    Write-Host "  ERROR: El servidor no responde." -ForegroundColor Red
    return $false
}

function Test-ModelQuality {
    param(
        [string]$modelName
    )
    Write-Host "`nProbando modelo: $modelName" -ForegroundColor Cyan
    $results = @()
    $promptIndex = 1
    foreach ($prompt in $prompts) {
        Write-Host "  [$promptIndex/6] Prompt: $($prompt.Substring(0, [Math]::Min(60, $prompt.Length)))..." -ForegroundColor Gray
        $body = @{
            model = "qwen"
            messages = @(@{role = "user"; content = $prompt})
            max_tokens = 4096   # Aumentado a 4096 para evitar truncamiento
            temperature = 0.6
            top_k = 20
            top_p = 0.95
            repeat_penalty = 1.05
            presence_penalty = 0.0
            frequency_penalty = 0.1
            stream = $false
        } | ConvertTo-Json -Depth 3

        $answer = $null
        $finishReason = $null
        $retries = 0
        $maxRetries = 3
        while ($retries -lt $maxRetries -and $answer -eq $null) {
            try {
                $response = Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json" -Body $body -ErrorAction Stop
                $answer = $response.choices[0].message.content
                $finishReason = $response.choices[0].finish_reason
                if ([string]::IsNullOrWhiteSpace($answer)) {
                    throw "Respuesta vacía"
                }
            } catch {
                $retries++
                if ($retries -lt $maxRetries) {
                    Write-Host "    Error: $($_.Exception.Message). Reintentando ($retries/$maxRetries)..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 2
                } else {
                    $answer = "ERROR: $_"
                    $finishReason = "error"
                }
            }
        }
        $results += [PSCustomObject]@{
            prompt = $prompt
            answer = $answer
            finish_reason = $finishReason
            timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        $promptIndex++
        Start-Sleep -Milliseconds 500
    }
    $outputFile = Join-Path $outDir "${modelName}_responses.json"
    $results | ConvertTo-Json -Depth 5 | Set-Content -Path $outputFile -Encoding UTF8
    Write-Host "  Resultados guardados en $outputFile" -ForegroundColor Green
}

Write-Host "===== COMPARACION DE CALIDAD ENTRE MODELOS (V2) =====" -ForegroundColor Yellow

if (-not (Wait-ForServer)) {
    Write-Host "Abortando prueba." -ForegroundColor Red
    exit 1
}

Write-Host "Primera fase: modelo ESTANDAR (Q4_K_M)" -ForegroundColor Yellow
Read-Host "Presiona Enter cuando el servidor este listo con el modelo estandar"
if (-not (Wait-ForServer)) { exit 1 }
Test-ModelQuality -modelName "standard_q4_km"

Write-Host "`nSegunda fase: modelo REPARADO (IQ4_NL)" -ForegroundColor Yellow
Read-Host "Presiona Enter despues de cambiar el modelo y reiniciar el servidor"
if (-not (Wait-ForServer)) { exit 1 }
Test-ModelQuality -modelName "repaired_iq4_nl"

Write-Host "`nPrueba completada. Revisa los archivos en $outDir" -ForegroundColor Green
Write-Host "Abre ambos JSON y busca el campo 'finish_reason': si aparece 'length' significa que la respuesta se trunco y deberias aumentar max_tokens." -ForegroundColor Cyan