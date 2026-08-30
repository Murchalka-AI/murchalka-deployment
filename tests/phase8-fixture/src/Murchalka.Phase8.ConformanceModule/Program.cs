using Murchalka.ModuleSdk.ProcessHost;
using Murchalka.Phase8.ConformanceModule;

if (Environment.GetEnvironmentVariable("MURCHALKA_MODULE_VERSION") == "0.5.1")
    throw new InvalidOperationException("Intentional Phase 8 activation failure used to verify Runtime rollback.");

using var shutdown = new CancellationTokenSource();
Console.CancelKeyPress += (_, eventArgs) =>
{
    eventArgs.Cancel = true;
    shutdown.Cancel();
};

await ModuleProcessHost.RunAsync(new FixtureModuleService(), shutdown.Token);
