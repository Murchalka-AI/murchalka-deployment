using Murchalka.ModuleProtocol.Json;
using Xunit;

namespace Murchalka.Deployment.Tests;

/// <summary>Verifies canonical profile and binding schemas.</summary>
public sealed class ProfileSchemaTests
{
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
}

