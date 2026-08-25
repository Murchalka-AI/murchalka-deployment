using System.Text.Json;
using System.Text.Json.Nodes;

namespace Murchalka.Deployment.Security;

internal static class CanonicalJson
{
    public static byte[] Serialize(JsonNode node)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream)) Write(writer, node);
        return stream.ToArray();
    }

    private static void Write(Utf8JsonWriter writer, JsonNode? node)
    {
        switch (node)
        {
            case null:
                writer.WriteNullValue();
                break;
            case JsonObject value:
                writer.WriteStartObject();
                foreach (var pair in value.OrderBy(pair => pair.Key, StringComparer.Ordinal))
                {
                    writer.WritePropertyName(pair.Key);
                    Write(writer, pair.Value);
                }

                writer.WriteEndObject();
                break;
            case JsonArray value:
                writer.WriteStartArray();
                foreach (var item in value) Write(writer, item);
                writer.WriteEndArray();
                break;
            case JsonValue value:
                value.WriteTo(writer);
                break;
            default:
                throw new InvalidOperationException($"Unsupported JSON node '{node.GetType().Name}'.");
        }
    }
}
