# quality_test_v5-wp-high.ps1
# Compara calidad y rendimiento entre modelos (usando la API)
# WordPress (2 high)
# max_tokens aumentado a 31862 para contexto más realista tras interacción prolongada

$prompts = @(
    @{
        text = "Crea un plugin de WordPress completo que registre un Custom Post Type 'eventos' con taxonomia personalizada 'categorias-evento'. Debe incluir: pagina admin propia con tabla personalizada usando WP_List_Table, meta boxes para fecha/lugar/precio, shortcode [eventos_proximos] que muestre eventos ordenados por fecha con paginacion, hooks wp_enqueue_script para CSS/JS propios, y sanitizacion/validacion completa de inputs."
        category = "wordpress"
        complexity = "high"
    },
    @{
        text = "Desarrolla una extension de WordPress para sincronizar productos externos via REST API: debe incluir clase principal con hook init, cron schedule para sync automatica cada X horas, endpoint wp_remote_get con timeout/retry, parseo de response JSON y creacion/actualizacion de productos como CPT 'producto', meta fields para precio/stock/imagen_url, action 'wp' para limpieza de transients caducados, y logging via WP_Error. Incluye comentario DocBlock en cada metodo."
        category = "wordpress"
        complexity = "high"
    }
)

$outDir = "C:\llama-benchmark\model_comparison_v5-wp"
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

    foreach ($item in $prompts) {
        $prompt = $item.text
        $category = $item.category
        $complexity = $item.complexity
        
        Write-Host "  [$promptIndex/2] ($category/$complexity) Prompt: $($prompt.Substring(0, [Math]::Min(60, $prompt.Length)))..." -ForegroundColor Gray

        $body = @{
            model = "qwen"
            messages = @(@{role = "user"; content = $prompt})
            max_tokens = 31862
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
            category = $category
            complexity = $complexity
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
    $outputFile = Join-Path $outDir "${modelName}_responses_v5-wp-high.json"
    $results | ConvertTo-Json -Depth 5 | Set-Content -Path $outputFile -Encoding UTF8
    Write-Host "  Resultados guardados en $outputFile" -ForegroundColor Green
}

# --- Ejecución principal ---
Write-Host "===== COMPARACION DE CALIDAD Y RENDIMIENTO (V5) =====" -ForegroundColor Yellow
Write-Host "Estructura: 4x backend (2 medium + 2 high) + 2x wordpress (high)" -ForegroundColor Yellow
Write-Host "max_tokens: 31862 (contexto extendido para respuestas largas)" -ForegroundColor Yellow
Write-Host "Asegurate de que el servidor esta corriendo con el modelo ESTANDAR (y --metrics activado si quieres tiempos detallados)." -ForegroundColor Yellow
Read-Host "Presiona Enter cuando este listo"
Test-ModelQuality -modelName "standard_q4_km"

Write-Host "`nPrueba completada. Revisa los archivos en $outDir" -ForegroundColor Green
