# benchmark tests

## configuración actual en llama.cpp

server.bat

```cmd
@echo off
.\llama-server.exe ^
  -m "C:\Users\estravagancia\.lmstudio\models\lmstudio-community\Qwen3.6-35B-A3B-GGUF\Qwen3.6-35B-A3B-Q4_K_M.gguf" ^
  -c 98304 ^
  -ngl 99 ^
  -np 1 ^
  --chat-template-kwargs "{\"preserve_thinking\":true}" ^
  --n-cpu-moe 12 ^
  --no-mmap ^
  --flash-attn on ^
  --ubatch-size 128 ^
  --cache-type-k q4_0 ^
  --cache-type-v q4_0 ^
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

## Para poder usarlo desde OpenCode añadiendolo como proveedor

proxy.bat

```cmd
@echo off
uvx oai2ollama --base-url http://localhost:8080/v1 --api-key sk-no-key-required
```

### opencode.json

```
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