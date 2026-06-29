# tools/functions/_common/

Provider-agnostic tool definitions. This is the canonical source for each
tool's logical schema: name, description, parameters, and return shape.

Provider-specific directories (`../anthropic/`, `../openai/`) contain thin
binding shims that adapt these schemas to each provider's format.

## File naming

`{tool-name}.schema.json` — JSON Schema for the tool's input parameters.

## Example

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "get_weather",
  "description": "Return current weather for a location.",
  "type": "object",
  "properties": {
    "location": {
      "type": "string",
      "description": "City name or lat/lng pair."
    },
    "unit": {
      "type": "string",
      "enum": ["celsius", "fahrenheit"],
      "default": "celsius"
    }
  },
  "required": ["location"]
}
```
