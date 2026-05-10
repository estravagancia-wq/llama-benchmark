# benchmark tests

Para mis pruebas personales.

- Windows 11
- llama.cpp
- ROCm

La intención es tener un asistente de código... Y parece que funciona relativamente bien.

Gracias a todos los que comparten sus experiencias. 
Por ejemplo al autor de este vídeo: <https://youtu.be/8F_5pdcD3HY?is=w3ZeQmp1uI410so-> @Codacus que abrió otro campo donde seguir curioseando, no digo investigando porque no soy un profesional.

Cacharreo, hago pruebas y saco mis conclusiones... Para que corra lo mejor que pueda en mi PC.

## configuración actual en llama.cpp

server.bat (se ejecuta el primero)

```bat
@echo off
.\llama-server.exe ^
  -m "C:\Users\estravagancia\.lmstudio\models\lmstudio-community\Qwen3.6-35B-A3B-GGUF\Qwen3.6-35B-A3B-Q4_K_M.gguf" ^
  -c 65536 ^
  -ngl 99 ^
  -np 1 ^
  --chat-template-kwargs "{\"preserve_thinking\":true}" ^
  --n-cpu-moe 8 ^
  --flash-attn on ^
  --cache-type-k q4_0 ^
  --cache-type-v q4_0 ^
  --no-mmap ^
  --ubatch-size 64 ^
  -b 512 ^
  --temp 0.6 ^
  --top-k 20 ^
  --top-p 0.95 ^
  --repeat-penalty 1.05 ^
  --repeat-last-n 256 ^
  --presence-penalty 0.0 ^
  --frequency-penalty 0.1 ^
  --mirostat 0 ^
  --host 0.0.0.0 ^
  --port 8080
```

## openCode

openCode  (se ejecuta a continuación, una vez cargado el servidor)

### opdencode.json

```json
"model": "llama-cpp/qwen3.6-35b-a3b",
  "permission": {
    "bash": {
      "*": "allow",
      "git commit *": "ask",
      "git push": "ask",
      "git push *": "ask",
      "git push --force *": "ask",
      "git rebase *": "ask",
      "git reset --hard *": "ask"
    },
    "read": {
      "*": "allow",
      "**.env": "deny",
      "**.env.*": "deny",
      "**/.env": "deny",
      "**/.env.*": "deny",
      "**/credentials.json": "deny",
      "**/secrets/**": "deny",
      "*.env": "deny",
      "*.env.*": "deny"
    }
  },

    ... ...

  "provider": {
    "llama-cpp": {
      "name": "Llama-CPP",
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://localhost:8080/v1",
        "chatTemplateKwargs": "{\"preserve_thinking\":true}"
      },
      "models": {
        "qwen3.6-35b-a3b": {
          "name": "qwen3.6-35b-a3b",
          "maxContextTokens": 98304
        }
      }
    }
  },
```

# Notas:

Si, me descargué el modelo usando LM Studio y lo corro desde llama.cpp :D (me resulta más cómodo descargarlos desde LM Studio, y ver las notas).

# Equipo

- Caja: Antec P30 AIR
- Cooling: Arctic Liquid Freezer III Pro
- MB: ASUS PRIME X870-P WIFI
- CPU: AMD Ryzen 7 9800X3D 4.7/5.2GHz
- SSD: WD_BLACK SN850X 2TB
- GPU: AMD Radeon RX 9070 XT (16 GB)
- RAM Corsair Vengeance RGB DDR5 6400MHz (CMH32GX5M2B6400C36w)
- PS: CORSAIR HX850