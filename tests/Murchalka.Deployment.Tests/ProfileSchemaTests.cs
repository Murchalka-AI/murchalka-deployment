using System.Text.Json.Nodes;
using Murchalka.ModuleProtocol.Json;
using Xunit;

namespace Murchalka.Deployment.Tests;

/// <summary>Verifies canonical profile and binding schemas.</summary>
public sealed class ProfileSchemaTests
{
    /// <summary>Verifies the coordinated Phase 7 Client Runtime component set.</summary>
    [Fact]
    public void ClientRuntimeLockPinsEveryPhaseSevenRepository()
    {
        var root = RepositoryRootLocator.Find();
        var document = JsonNode.Parse(File.ReadAllText(Path.Combine(root, "releases", "client-runtime.lock.json")))!.AsObject();
        var components = document["components"]!.AsArray();
        var tags = components.ToDictionary(
            value => value!["repository"]!.GetValue<string>(),
            value => value!["tag"]!.GetValue<string>(),
            StringComparer.Ordinal);
        Assert.Equal(7, document["phase"]!.GetValue<int>());
        Assert.Equal("v0.4.0", document["deploymentTag"]!.GetValue<string>());
        Assert.Equal(10, tags.Count);
        Assert.Equal("v0.4.1", tags["murchalka-client-runtime"]);
        Assert.Equal("v0.4.1", tags["murchalka-web"]);
        Assert.Equal("v0.4.1", tags["murchalka-desktop"]);
        Assert.Equal("v0.4.2", tags["murchalka-module-client-diagnostics"]);
        Assert.All(
            tags.Where(component => component.Key is not (
                "murchalka-client-runtime" or
                "murchalka-web" or
                "murchalka-desktop" or
                "murchalka-module-client-diagnostics")),
            component => Assert.Equal("v0.4.0", component.Value));
        Assert.All(tags.Values, tag => Assert.Matches("^v[0-9]+\\.[0-9]+\\.[0-9]+$", tag));
    }

    /// <summary>Verifies that the Minimal Core profile satisfies the canonical profile schema.</summary>
    [Fact]
    public void MinimalProfileIsValid()
    {
        var root = RepositoryRootLocator.Find();
        var document = StructuredDocument.Load(Path.Combine(root, "profiles", "minimal", "murchalka.profile.yaml"));
        var report = CanonicalSchemaValidator.CreateBundled().ValidateJson("profile.schema.json", document);

        Assert.True(report.IsValid, string.Join(Environment.NewLine, report.Violations.Select(value => value.Message)));
    }

    /// <summary>Verifies that deterministic Minimal Core bindings satisfy the canonical binding schema.</summary>
    [Fact]
    public void MinimalBindingsAreValid()
    {
        var root = RepositoryRootLocator.Find();
        var document = StructuredDocument.Load(Path.Combine(root, "bindings", "minimal.bindings.yaml"));
        var report = CanonicalSchemaValidator.CreateBundled().ValidateJson("binding.schema.json", document);

        Assert.True(report.IsValid, string.Join(Environment.NewLine, report.Violations.Select(value => value.Message)));
    }

    /// <summary>Verifies that the Minimal Core graph contains every required Phase 5 module and routing edge.</summary>
    [Fact]
    public void MinimalProfileContainsCompletePhaseFiveComposition()
    {
        var root = RepositoryRootLocator.Find();
        var profile = StructuredDocument.Load(Path.Combine(root, "profiles", "minimal", "murchalka.profile.yaml")).AsObject();
        var moduleIds = profile["modules"]!["required"]!.AsArray()
            .Select(module => module!["id"]!.GetValue<string>())
            .ToHashSet(StringComparer.Ordinal);
        Assert.Equal(17, moduleIds.Count);
        Assert.Contains("dev.murchalka.model-catalog", moduleIds);
        Assert.Contains("dev.murchalka.model-router-basic", moduleIds);
        Assert.Contains("dev.murchalka.observability", moduleIds);

        var bindings = StructuredDocument.Load(Path.Combine(root, "bindings", "minimal.bindings.yaml")).AsObject()["bindings"]!.AsArray();
        Assert.Contains(bindings, binding => binding!["id"]!.GetValue<string>() == "agent-model" && binding["provider"]!["module"]!.GetValue<string>() == "dev.murchalka.model-router-basic");
        Assert.Contains(bindings, binding => binding!["id"]!.GetValue<string>() == "router-provider" && binding["provider"]!["module"]!.GetValue<string>() == "dev.murchalka.model-ollama");
    }

    /// <summary>Verifies that the immutable component lock covers the complete Minimal Core graph.</summary>
    [Fact]
    public void MinimalComponentLockMatchesProfileModules()
    {
        var root = RepositoryRootLocator.Find();
        var profile = StructuredDocument.Load(Path.Combine(root, "profiles", "minimal", "murchalka.profile.yaml")).AsObject();
        var profileModuleIds = profile["modules"]!["required"]!.AsArray()
            .Select(module => module!["id"]!.GetValue<string>())
            .ToHashSet(StringComparer.Ordinal);

        var lockPath = Path.Combine(root, "releases", "minimal-core.lock.json");
        var componentLock = JsonNode.Parse(File.ReadAllText(lockPath))!.AsObject();
        var lockedModules = componentLock["modules"]!.AsArray();
        var lockedModuleIds = lockedModules
            .Select(module => module!["moduleId"]!.GetValue<string>())
            .ToHashSet(StringComparer.Ordinal);
        var lockedRepositories = lockedModules
            .Select(module => module!["repository"]!.GetValue<string>())
            .ToHashSet(StringComparer.Ordinal);
        var lockedTags = lockedModules.ToDictionary(
            module => module!["repository"]!.GetValue<string>(),
            module => module!["tag"]!.GetValue<string>(),
            StringComparer.Ordinal);

        Assert.Equal("v0.3.4", componentLock["deploymentTag"]!.GetValue<string>());
        Assert.Equal("v0.3.3", componentLock["runtime"]!["tag"]!.GetValue<string>());
        Assert.Equal("v0.2.18", componentLock["web"]!["tag"]!.GetValue<string>());
        Assert.All(lockedTags.Values, tag => Assert.Equal("v0.3.3", tag));
        Assert.Equal("v0.3.2", componentLock["node"]!["admin"]!["tag"]!.GetValue<string>());
        Assert.Equal("v0.3.2", componentLock["node"]!["controller"]!["tag"]!.GetValue<string>());
        Assert.Equal("v0.3.4", componentLock["node"]!["runtime"]!["tag"]!.GetValue<string>());
        Assert.Equal("v0.3.4", componentLock["node"]!["diagnostics"]!["tag"]!.GetValue<string>());
        Assert.True(profileModuleIds.SetEquals(lockedModuleIds));
        Assert.Equal(17, lockedRepositories.Count);
        Assert.All(lockedModules, module => Assert.Matches("^v[0-9]+\\.[0-9]+\\.[0-9]+$", module!["tag"]!.GetValue<string>()));
    }

    /// <summary>Verifies that clean-install bootstrap documents start at revision one and use snapshot envelopes.</summary>
    [Fact]
    public void BootstrapDocumentsStartAtFirstRevision()
    {
        var root = RepositoryRootLocator.Find();
        var bindings = StructuredDocument.Load(Path.Combine(root, "bindings", "minimal.bindings.yaml")).AsObject();
        Assert.Equal(1, bindings["metadata"]!["revision"]!.GetValue<int>());

        var configurationPaths = Directory.GetFiles(
            Path.Combine(root, "configuration"),
            "dev.murchalka.*.json",
            SearchOption.TopDirectoryOnly);
        Assert.NotEmpty(configurationPaths);
        Assert.All(configurationPaths, path =>
        {
            var snapshot = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
            Assert.Equal(1, snapshot["revision"]!.GetValue<int>());
            Assert.IsType<JsonObject>(snapshot["values"]);
        });
    }

    /// <summary>Verifies that the Runtime container permits rootless Bubblewrap without restoring outer capabilities.</summary>
    [Fact]
    public void RuntimeContainerSupportsNestedModuleSandbox()
    {
        var root = RepositoryRootLocator.Find();
        var compose = StructuredDocument.Load(Path.Combine(root, "compose", "compose.yaml")).AsObject();
        var runtime = compose["services"]!["runtime"]!.AsObject();
        var moduleLoader = compose["services"]!["module-loader"]!.AsObject();
        var sandboxProbe = compose["services"]!["sandbox-probe"]!.AsObject();
        var securityOptions = runtime["security_opt"]!.AsArray()
            .Select(option => option!.GetValue<string>())
            .ToHashSet(StringComparer.Ordinal);
        var droppedCapabilities = runtime["cap_drop"]!.AsArray()
            .Select(capability => capability!.GetValue<string>())
            .ToHashSet(StringComparer.Ordinal);

        Assert.True(runtime["read_only"]!.GetValue<bool>());
        Assert.Contains("no-new-privileges:true", securityOptions);
        Assert.Contains("seccomp=unconfined", securityOptions);
        Assert.Contains("apparmor=unconfined", securityOptions);
        Assert.Contains("systempaths=unconfined", securityOptions);
        Assert.True(droppedCapabilities.SetEquals(["ALL"]));
        Assert.Equal("host", runtime["userns_mode"]!.GetValue<string>());
        Assert.Null(runtime["secrets"]);
        Assert.Contains(
            "/var/lib/murchalka/configuration/admin-token",
            runtime["command"]!.AsArray().Select(argument => argument!.GetValue<string>()));
        Assert.Contains(
            "../runtime/security:/security:ro",
            moduleLoader["volumes"]!.AsArray().Select(volume => volume!.GetValue<string>()));
        Assert.Equal("/usr/local/libexec/murchalka-netns-exec", sandboxProbe["entrypoint"]!.AsArray()[0]!.GetValue<string>());
        Assert.Equal(
            "namespace-launcher",
            runtime["environment"]!["MURCHALKA_LINUX_NETWORK_ISOLATION"]!.GetValue<string>());
        var probeCommand = sandboxProbe["command"]!.AsArray()
            .Select(argument => argument!.GetValue<string>())
            .ToHashSet(StringComparer.Ordinal);
        Assert.Contains("/usr/bin/bwrap", probeCommand);
        Assert.DoesNotContain("--unshare-all", probeCommand);
        Assert.DoesNotContain("--unshare-user", probeCommand);
        Assert.DoesNotContain("--unshare-net", probeCommand);
        Assert.DoesNotContain("--share-net", probeCommand);
        Assert.Contains("--unshare-ipc", probeCommand);
        Assert.Contains("--unshare-pid", probeCommand);
        Assert.Contains("--unshare-uts", probeCommand);
        Assert.DoesNotContain("--unshare-cgroup", probeCommand);
        Assert.DoesNotContain("--unshare-cgroup-try", probeCommand);
        Assert.Equal("host", sandboxProbe["userns_mode"]!.GetValue<string>());
        Assert.True(sandboxProbe["cap_drop"]!.AsArray()
            .Select(capability => capability!.GetValue<string>())
            .ToHashSet(StringComparer.Ordinal)
            .SetEquals(["ALL"]));
        Assert.True(securityOptions.SetEquals(sandboxProbe["security_opt"]!.AsArray()
            .Select(option => option!.GetValue<string>())));
        Assert.Equal(
            "service_completed_successfully",
            runtime["depends_on"]!["sandbox-probe"]!["condition"]!.GetValue<string>());
    }

    /// <summary>Verifies that Phase 6 services receive only their least-privilege secrets through isolated volumes.</summary>
    [Fact]
    public void PhaseSixSecretsAreStagedForRootlessServices()
    {
        var root = RepositoryRootLocator.Find();
        var compose = StructuredDocument.Load(Path.Combine(root, "compose", "compose.phase6.yaml")).AsObject();
        var services = compose["services"]!.AsObject();
        var loader = services["node-security-loader"]!.AsObject();
        var controller = services["node-controller"]!.AsObject();
        var node = services["node"]!.AsObject();

        Assert.Equal("none", loader["network_mode"]!.GetValue<string>());
        Assert.True(loader["read_only"]!.GetValue<bool>());
        Assert.True(loader["cap_drop"]!.AsArray()
            .Select(capability => capability!.GetValue<string>())
            .ToHashSet(StringComparer.Ordinal)
            .SetEquals(["ALL"]));
        Assert.True(loader["cap_add"]!.AsArray()
            .Select(capability => capability!.GetValue<string>())
            .ToHashSet(StringComparer.Ordinal)
            .SetEquals(["CHOWN", "DAC_OVERRIDE", "FOWNER"]));

        var controllerVolumes = controller["volumes"]!.AsArray()
            .Select(volume => volume!.GetValue<string>())
            .ToHashSet(StringComparer.Ordinal);
        var nodeVolumes = node["volumes"]!.AsArray()
            .Select(volume => volume!.GetValue<string>())
            .ToHashSet(StringComparer.Ordinal);
        Assert.Contains("node-controller-secrets:/run/secrets:ro", controllerVolumes);
        Assert.Contains("node-runtime-secrets:/run/secrets:ro", nodeVolumes);
        Assert.DoesNotContain("../runtime/node-security:/run/secrets:ro", controllerVolumes);
        Assert.DoesNotContain("../runtime/node-security:/run/secrets:ro", nodeVolumes);
        Assert.Equal(
            "service_completed_successfully",
            controller["depends_on"]!["node-security-loader"]!["condition"]!.GetValue<string>());
    }
}
