using System.Text.Json;
using Murchalka.ModuleSdk.ProcessHost;

namespace Murchalka.Phase8.ConformanceModule;

internal sealed class FixtureModuleService : IModuleService
{
    public async ValueTask<JsonElement> HandleAsync(
        ModuleInvocationContext context,
        JsonElement request,
        IModuleDependencyClient dependencies,
        CancellationToken cancellationToken)
    {
        _ = dependencies;
        var delay = request.TryGetProperty("delayMilliseconds", out var value)
            ? value.GetInt32()
            : context.Capability == "conformance.agent-turn" ? 3000 : 1000;
        if (delay is < 0 or > 30000) throw new InvalidDataException("delayMilliseconds must be between 0 and 30000.");
        await Task.Delay(TimeSpan.FromMilliseconds(delay), cancellationToken).ConfigureAwait(false);
        return JsonSerializer.SerializeToElement(new { ok = true, capability = context.Capability, received = request });
    }
}
