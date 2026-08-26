using System.Net.Http.Json;
using System.Net.Http.Headers;
using System.Net.WebSockets;
using System.Text.Json;

namespace Murchalka.Phase5.Acceptance;

internal static class Program
{
    private const int MaximumMessageBytes = 1_048_576;

    /// <summary>Runs the Phase 5 deployment acceptance scenario.</summary>
    /// <param name="args">Optional runtime and realtime endpoint arguments.</param>
    /// <returns>Zero when every assertion succeeds.</returns>
    public static async Task<int> Main(string[] args)
    {
        try
        {
            var options = ParseOptions(args);
            var runtimeUri = LoopbackUri(options.GetValueOrDefault("runtime", "http://127.0.0.1:5078"), "http");
            var realtimeUri = LoopbackUri(options.GetValueOrDefault("realtime", "ws://127.0.0.1:5080/v1/realtime"), "ws");
            var username = options.GetValueOrDefault("username", "owner");
            var adminTokenPath = options.GetValueOrDefault("admin-token-file")
                ?? throw new ArgumentException("--admin-token-file is required.");
            var adminToken = (await File.ReadAllTextAsync(adminTokenPath).ConfigureAwait(false)).Trim();
            if (adminToken.Length < 43) throw new InvalidDataException("The administrative token file is invalid.");
            var evidencePath = options.GetValueOrDefault("evidence");
            var password = await Console.In.ReadLineAsync().ConfigureAwait(false);
            if (string.IsNullOrEmpty(password)) throw new InvalidDataException("A password must be supplied on standard input.");

            using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(5));
            await RunAsync(runtimeUri, realtimeUri, username, password, adminToken, evidencePath, timeout.Token).ConfigureAwait(false);
            Console.WriteLine("Phase 5 acceptance passed: realtime auth, Agent UI, session, agent, persisted history, and audit evidence are healthy.");
            return 0;
        }
        catch (Exception exception) when (exception is ArgumentException or HttpRequestException or InvalidDataException or JsonException or WebSocketException or OperationCanceledException)
        {
            Console.Error.WriteLine(exception.Message);
            return 1;
        }
    }

    private static async Task RunAsync(Uri runtimeUri, Uri realtimeUri, string username, string password, string adminToken, string? evidencePath, CancellationToken cancellationToken)
    {
        string conversationId;
        string sessionId;
        if (evidencePath is not null)
        {
            var evidence = JsonSerializer.Deserialize<JsonElement>(await File.ReadAllTextAsync(evidencePath, cancellationToken).ConfigureAwait(false));
            conversationId = RequiredString(evidence, "conversationId");
            sessionId = RequiredString(evidence, "sessionId");
        }
        else
        {
            conversationId = "acceptance-" + Guid.NewGuid().ToString("N");
            var turnId = "acceptance-turn-" + Guid.NewGuid().ToString("N");
            using var socket = new ClientWebSocket();
            await socket.ConnectAsync(realtimeUri, cancellationToken).ConfigureAwait(false);
            await SendAsync(socket, new { type = "authenticate", username, password }, cancellationToken).ConfigureAwait(false);
            RequireType(await ReceiveAsync(socket, cancellationToken).ConfigureAwait(false), "authenticated");
            await SendAsync(socket, new { type = "ui.get", conversationId }, cancellationToken).ConfigureAwait(false);
            var ui = await ReceiveAsync(socket, cancellationToken).ConfigureAwait(false);
            RequireType(ui, "ui.document");
            if (!ui.TryGetProperty("document", out var document) || document.ValueKind != JsonValueKind.Object)
                throw new InvalidDataException("Agent UI did not return a document.");
            await SendAsync(socket, new { type = "turn", conversationId, text = "Reply with one short greeting.", idempotencyKey = turnId }, cancellationToken).ConfigureAwait(false);
            var turn = await ReceiveAsync(socket, cancellationToken).ConfigureAwait(false);
            RequireType(turn, "turn.completed");
            sessionId = RequiredString(turn, "sessionId");
            var assistant = turn.GetProperty("result").GetProperty("message").GetProperty("content").GetString();
            if (string.IsNullOrWhiteSpace(assistant)) throw new InvalidDataException("The model returned an empty assistant response.");
            await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, "acceptance-complete", cancellationToken).ConfigureAwait(false);
        }

        using var http = new HttpClient { BaseAddress = runtimeUri, Timeout = TimeSpan.FromSeconds(30) };
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", adminToken);
        var history = await InvokeAsync(http, "conversations.history", new { operation = "list", conversationId, limit = 10 }, cancellationToken).ConfigureAwait(false);
        var roles = history.GetProperty("messages").EnumerateArray().Select(value => value.GetProperty("role").GetString()).ToArray();
        if (!roles.Contains("user", StringComparer.Ordinal) || !roles.Contains("assistant", StringComparer.Ordinal))
            throw new InvalidDataException("Persisted conversation history does not contain both turn messages.");

        var audit = await InvokeAsync(http, "audit.store", new { operation = "query", limit = 500 }, cancellationToken).ConfigureAwait(false);
        if (!audit.GetProperty("events").EnumerateArray().Any(value =>
                value.GetProperty("kind").GetString() == "agent.turn" &&
                value.GetProperty("subject").GetString() == "conversation:" + conversationId &&
                value.GetProperty("outcome").GetString() == "succeeded"))
            throw new InvalidDataException("Product audit does not contain successful agent-turn evidence.");

        for (var attempt = 0; attempt < 20; attempt++)
        {
            var session = await InvokeAsync(http, "sessions.manage", new { operation = "get", sessionId }, cancellationToken).ConfigureAwait(false);
            if (session.GetProperty("session").GetProperty("state").GetString() == "closed") return;
            await Task.Delay(TimeSpan.FromMilliseconds(250), cancellationToken).ConfigureAwait(false);
        }

        throw new InvalidDataException("The realtime connection did not close its durable session.");
    }

    private static async Task<JsonElement> InvokeAsync(HttpClient client, string capability, object payload, CancellationToken cancellationToken)
    {
        using var response = await client.PostAsJsonAsync($"/v1/capabilities/{capability}/invoke", new { payload }, cancellationToken).ConfigureAwait(false);
        var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode) throw new InvalidDataException($"Administrative invocation of '{capability}' failed ({(int)response.StatusCode}): {body}");
        return JsonSerializer.Deserialize<JsonElement>(body);
    }

    private static async Task SendAsync(ClientWebSocket socket, object message, CancellationToken cancellationToken) =>
        await socket.SendAsync(JsonSerializer.SerializeToUtf8Bytes(message), WebSocketMessageType.Text, true, cancellationToken).ConfigureAwait(false);

    private static async Task<JsonElement> ReceiveAsync(ClientWebSocket socket, CancellationToken cancellationToken)
    {
        var buffer = new byte[MaximumMessageBytes];
        var result = await socket.ReceiveAsync(buffer, cancellationToken).ConfigureAwait(false);
        if (result.MessageType != WebSocketMessageType.Text || !result.EndOfMessage || result.Count == 0)
            throw new InvalidDataException("Realtime returned an invalid response frame.");
        return JsonSerializer.Deserialize<JsonElement>(buffer.AsSpan(0, result.Count));
    }

    private static void RequireType(JsonElement response, string expected)
    {
        var actual = RequiredString(response, "type");
        if (actual == "error") throw new InvalidDataException($"Realtime error: {response.GetProperty("code").GetString()}: {response.GetProperty("message").GetString()}");
        if (actual != expected) throw new InvalidDataException($"Expected realtime response '{expected}', received '{actual}'.");
    }

    private static string RequiredString(JsonElement document, string property) =>
        document.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(value.GetString())
            ? value.GetString()!
            : throw new InvalidDataException($"Realtime property '{property}' must be a non-empty string.");

    private static Uri LoopbackUri(string value, string scheme)
    {
        var uri = new Uri(value, UriKind.Absolute);
        if (uri.Scheme != scheme || !System.Net.IPAddress.TryParse(uri.Host, out var address) || !System.Net.IPAddress.IsLoopback(address) || !string.IsNullOrEmpty(uri.UserInfo))
            throw new ArgumentException($"Endpoint '{value}' must use an explicit loopback address and an allowed scheme.");
        return uri;
    }

    private static Dictionary<string, string> ParseOptions(string[] args)
    {
        if (args.Length % 2 != 0) throw new ArgumentException("Usage: [--runtime URL] [--realtime URL] [--username NAME] --admin-token-file PATH, with password on standard input.");
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        for (var index = 0; index < args.Length; index += 2)
        {
            var name = args[index];
            if (name is not ("--runtime" or "--realtime" or "--username" or "--admin-token-file" or "--evidence") || !result.TryAdd(name[2..], args[index + 1]))
                throw new ArgumentException($"Unknown or duplicate option '{name}'.");
        }

        return result;
    }
}
