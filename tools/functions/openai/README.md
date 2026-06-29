# tools/functions/openai/

OpenAI-format function definitions. Each file matches the `tools[]` array
entry format accepted by the OpenAI Chat Completions API.

## Format

```json
{
  "type": "function",
  "function": {
    "name": "get_weather",
    "description": "Return current weather for a location.",
    "parameters": {
      "$ref": "../_common/get_weather.schema.json"
    }
  }
}
```
