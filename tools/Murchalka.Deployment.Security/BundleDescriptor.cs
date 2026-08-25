using System.Text.Json.Nodes;

namespace Murchalka.Deployment.Security;

internal sealed record BundleDescriptor(
    string ModuleId,
    string Version,
    string Publisher,
    string PublisherKeyId,
    string BundleDigest,
    JsonNode Permissions,
    byte[] SignedContent,
    byte[] Signature);
