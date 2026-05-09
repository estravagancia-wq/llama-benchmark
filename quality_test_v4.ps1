# quality_test_v4.ps1
# Compara calidad y rendimiento entre modelos (usando la API)
# El servidor debe estar corriendo en http://localhost:8080 con --metrics opcional

$prompts = @(
    "Escribe una funcion PHP que valide una direccion de email usando filter_var y tambien una validacion extra (dominio no numerico, longitud maxima 255).",
    "Crea una clase PHP User con propiedades private: id, name, email, password. Incluye constructor, getters/setters, y un metodo validate() que devuelva true si email y password cumplen unos criterios basicos (email valido, password minimo 8 caracteres).",
    "Implementa una funcion recursiva factorial(`$n) en PHP que maneje numeros negativos lanzando una excepcion. Ademas, escribe los test unitarios usando PHPUnit para esta funcion.",
    "Escribe un snippet PHP que conecte a una base de datos MySQL usando PDO, ejecute una consulta SELECT con parametros seguros (prepared statement) y devuelva los resultados como un array asociativo. Incluye manejo de excepciones.",
    "Refactoriza el siguiente codigo PHP para que sea mas legible y use buenas practicas: function do(`$a,`$b){if(`$a>0){return `$a+`$b;}else{return `$a*`$b;}} (nota: 'do' es palabra reservada, cambiale el nombre).",
    "Explica con ejemplos de codigo la diferencia entre include, require, include_once y require_once en PHP. Cuando usar cada uno."
)

$outDir = "C:\llama-benchmark\model_comparison_v4"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$url = "http://localhost:8080/v1/chat/completions"
$metricsUrl = "http://localhost:8080/metrics"

# Detectar si el servidor tiene el endpoint /metrics
$hasMetrics = $false
try {
    $null = Invoke-RestMethod -Uri $metricsUrl -Method Get -ErrorAction Stop
    $hasMetrics = $true
    Write-Host "Endpoint /metrics detectado: se registrarán tiempos detallados." -ForegroundColor Green
} catch {
    Write-Host "Endpoint /metrics NO detectado. Solo se registrará tiempo total." -ForegroundColor Yellow
}

function Get-MetricsValues {
    <#
    .SYNOPSIS
    Obtiene las métricas acumuladas del servidor desde /metrics.
    Devuelve un objeto con prompt_eval_time_ms y eval_time_ms.
    Nota: parsea las líneas relevantes, asume formato Prometheus.
    #>
    $result = @{ prompt_eval_time_ms = 0; eval_time_ms = 0 }
    try {
        $metricsText = Invoke-RestMethod -Uri $metricsUrl -Method Get
        # Buscar líneas como: llama_prompt_eval_time_ms_total X.XX
        if ($metricsText -match 'llama_prompt_eval_time_ms_total\s+([\d\.]+)') {
            $result.prompt_eval_time_ms = [double]$Matches[1]
        }
        if ($metricsText -match 'llama_eval_time_ms_total\s+([\d\.]+)') {
            $result.eval_time_ms = [double]$Matches[1]
        }
    } catch {
        Write-Host "Error leyendo /metrics: $_" -ForegroundColor Red
    }
    return $result
}

function Test-ModelQuality {
    param(
        [string]$modelName
    )
    Write-Host "`n=== Probando modelo: $modelName ===" -ForegroundColor Cyan
    $results = @()
    $promptIndex = 1

    foreach ($prompt in $prompts) {
        Write-Host "  [$promptIndex/6] Prompt: $($prompt.Substring(0, [Math]::Min(60, $prompt.Length)))..." -ForegroundColor Gray

        $body = @{
            model = "qwen"
            messages = @(@{role = "user"; content = $prompt})
            max_tokens = 4096
            temperature = 0.6
            top_k = 20
            top_p = 0.95
            repeat_penalty = 1.05
            presence_penalty = 0.0
            frequency_penalty = 0.1
            stream = $false
        } | ConvertTo-Json -Depth 3

        # Medir tiempo total de la llamada HTTP
        $elapsed = Measure-Command {
            try {
                if ($hasMetrics) {
                    $metricsBefore = Get-MetricsValues
                }
                $response = Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json" -Body $body -ErrorAction Stop
                if ($hasMetrics) {
                    $metricsAfter = Get-MetricsValues
                }
            } catch {
                $response = $null
                Write-Host "    Error: $_" -ForegroundColor Red
            }
        }

        $answer = $null
        $finishReason = $null
        $usage = $null
        if ($response -ne $null) {
            $answer = $response.choices[0].message.content
            $finishReason = $response.choices[0].finish_reason
            $usage = $response.usage
        } else {
            $answer = "ERROR: La llamada a la API falló"
            $finishReason = "error"
        }

        # Calcular métricas si tenemos /metrics
        $promptEvalTimeMs = $null
        $evalTimeMs = $null
        $tokensPerSecond = $null
        if ($hasMetrics -and $response -ne $null -and $usage -ne $null) {
            $promptEvalTimeMs = $metricsAfter.prompt_eval_time_ms - $metricsBefore.prompt_eval_time_ms
            $evalTimeMs = $metricsAfter.eval_time_ms - $metricsBefore.eval_time_ms
            if ($evalTimeMs -gt 0 -and $usage.completion_tokens -gt 0) {
                $tokensPerSecond = ($usage.completion_tokens * 1000) / $evalTimeMs
                $tokensPerSecond = [Math]::Round($tokensPerSecond, 2)
            }
        }

        $result = [PSCustomObject]@{
            prompt = $prompt
            answer = $answer
            finish_reason = $finishReason
            total_time_ms = [Math]::Round($elapsed.TotalMilliseconds, 2)
            total_time_sec = [Math]::Round($elapsed.TotalSeconds, 2)
            prompt_tokens = if ($usage) { $usage.prompt_tokens } else { $null }
            completion_tokens = if ($usage) { $usage.completion_tokens } else { $null }
            prompt_eval_time_ms = $promptEvalTimeMs
            eval_time_ms = $evalTimeMs
            tokens_per_second = $tokensPerSecond
            timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        $results += $result
        $promptIndex++
        Start-Sleep -Milliseconds 200  # pausa corta para no saturar
    }
    $outputFile = Join-Path $outDir "${modelName}_responses.json"
    $results | ConvertTo-Json -Depth 5 | Set-Content -Path $outputFile -Encoding UTF8
    Write-Host "  Resultados guardados en $outputFile" -ForegroundColor Green
}

# --- Ejecución principal ---
Write-Host "===== COMPARACION DE CALIDAD Y RENDIMIENTO (V3) =====" -ForegroundColor Yellow
Write-Host "Asegurate de que el servidor esta corriendo con el modelo ESTANDAR (y --metrics activado si quieres tiempos detallados)." -ForegroundColor Yellow
Read-Host "Presiona Enter cuando este listo"
Test-ModelQuality -modelName "standard_q4_km"

# Write-Host "`nAhora cambia el modelo en el servidor al REPARADO (IQ4_NL) y reinicia el servidor." -ForegroundColor Yellow
# Read-Host "Presiona Enter cuando este listo"
# Test-ModelQuality -modelName "repaired_iq4_nl"

Write-Host "`nPrueba completada. Revisa los archivos en $outDir" -ForegroundColor Green