# quality_test.ps1
# Compara la calidad de codigo entre dos modelos (estandar vs reparado)
# El servidor debe estar corriendo en http://localhost:8080

$prompts = @(
    "Escribe una funcion PHP que valide una direccion de email usando filter_var y tambien una validacion extra (dominio no numerico, longitud maxima 255).",
    "Crea una clase PHP `User` con propiedades private: id, name, email, password. Incluye constructor, getters/setters, y un metodo `validate()` que devuelva true si email y password cumplen unos criterios basicos (email valido, password minimo 8 caracteres).",
    "Implementa una funcion recursiva `factorial($n)` en PHP que maneje numeros negativos lanzando una excepcion. Ademas, escribe los test unitarios usando PHPUnit para esta funcion.",
    "Escribe un snippet PHP que conecte a una base de datos MySQL usando PDO, ejecute una consulta SELECT con parametros seguros (prepared statement) y devuelva los resultados como un array asociativo. Incluye manejo de excepciones.",
    "Refactoriza el siguiente codigo PHP para que sea mas legible y use buenas practicas: `function do($a,$b){if($a>0){return $a+$b;}else{return $a*$b;}}` (nota: 'do' es palabra reservada, cambiale el nombre).",
    "Explica con ejemplos de codigo la diferencia entre `include`, `require`, `include_once` y `require_once` en PHP. Cuando usar cada uno."
)

$outDir = "C:\llama-benchmark\model_comparison"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$url = "http://localhost:8080/v1/chat/completions"

function Test-ModelQuality {
    param(
        [string]$modelName
    )
    Write-Host "`nProbando modelo: $modelName" -ForegroundColor Cyan
    $results = @()
    foreach ($prompt in $prompts) {
        Write-Host "  Prompt: $($prompt.Substring(0, [Math]::Min(60, $prompt.Length)))..." -ForegroundColor Gray
        $body = @{
            model = "qwen"
            messages = @(@{role = "user"; content = $prompt})
            max_tokens = 2048
            temperature = 0.6
            top_k = 20
            top_p = 0.95
            repeat_penalty = 1.05
            presence_penalty = 0.0
            frequency_penalty = 0.1
            stream = $false
        } | ConvertTo-Json -Depth 3
        try {
            $response = Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json" -Body $body
            $answer = $response.choices[0].message.content
            $results += [PSCustomObject]@{ prompt = $prompt; answer = $answer }
        } catch {
            $results += [PSCustomObject]@{ prompt = $prompt; answer = "ERROR: $_" }
        }
        Start-Sleep -Milliseconds 300
    }
    $outputFile = Join-Path $outDir "${modelName}_responses.json"
    $results | ConvertTo-Json -Depth 5 | Set-Content -Path $outputFile -Encoding UTF8
    Write-Host "  Resultados guardados en $outputFile" -ForegroundColor Green
}

Write-Host "===== COMPARACION DE CALIDAD ENTRE MODELOS =====" -ForegroundColor Yellow
Write-Host "Asegurate de que el servidor esta corriendo con el modelo ESTANDAR." -ForegroundColor Yellow
Read-Host "Presiona Enter cuando este listo"
Test-ModelQuality -modelName "standard_q4_km"

Write-Host "`nAhora cambia el modelo en el servidor al REPARADO (IQ4_NL) y reinicia el servidor." -ForegroundColor Yellow
Read-Host "Presiona Enter cuando este listo"
Test-ModelQuality -modelName "repaired_iq4_nl"

Write-Host "`nPrueba completada. Revisa los archivos en $outDir" -ForegroundColor Green