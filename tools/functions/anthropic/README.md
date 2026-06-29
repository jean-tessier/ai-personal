# tools/functions/anthropic/

Anthropic-format tool definitions. Each file is a JSON object matching the
`tools[]` array entry format accepted by the Anthropic Messages API.

Reference the canonical schema from `../_common/` rather than duplicating
parameter definitions.

## Format

```json
{
  "name": "get_weather",
  "description": "Return current weather for a location.",
  "input_schema": {
    "$ref": "../_common/get_weather.schema.json"
  }
}
```

In practice, `$ref` isn't resolved at runtime — use it as documentation.
Copy or inline the relevant fields when building actual API payloads.
