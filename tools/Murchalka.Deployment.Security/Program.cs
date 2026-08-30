using System.IO.Compression;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using Murchalka.ModuleProtocol.Json;

namespace Murchalka.Deployment.Security;

internal static class Program
{
    private const string Algorithm = "ecdsa-p256-sha256";
    private const string Publisher = "dev.murchalka";

    public static int Main(string[] args)
    {
        try
        {
            var options = ParseOptions(args);
            Prepare(
                Required(options, "bundles"),
                Required(options, "publisher-key"),
                Required(options, "publisher-key-id"),
                options.GetValueOrDefault("additional-publisher-key"),
                options.GetValueOrDefault("additional-publisher-key-id"),
                Required(options, "grant-private-key"),
                options.GetValueOrDefault("grant-key-id", "local-grants"),
                Required(options, "output"));
            return 0;
        }
        catch (Exception exception) when (exception is ArgumentException or IOException or InvalidDataException or JsonException or CryptographicException)
        {
            Console.Error.WriteLine(exception.Message);
            return 2;
        }
    }

    private static void Prepare(
        string bundlesPath,
        string publisherKeyPath,
        string publisherKeyId,
        string? additionalPublisherKeyPath,
        string? additionalPublisherKeyId,
        string grantPrivateKeyPath,
        string grantKeyId,
        string outputPath)
    {
        ValidateIdentifier(publisherKeyId, nameof(publisherKeyId));
        ValidateIdentifier(grantKeyId, nameof(grantKeyId));
        if ((additionalPublisherKeyPath is null) != (additionalPublisherKeyId is null))
            throw new ArgumentException("Additional publisher key path and identifier must be supplied together.");
        if (additionalPublisherKeyId is not null)
        {
            ValidateIdentifier(additionalPublisherKeyId, nameof(additionalPublisherKeyId));
            if (additionalPublisherKeyId == publisherKeyId) throw new ArgumentException("Publisher key identifiers must be unique.");
        }
        if (!Directory.Exists(bundlesPath)) throw new DirectoryNotFoundException($"Bundle directory '{bundlesPath}' was not found.");

        var bundlePaths = Directory.GetFiles(bundlesPath, "*.murchalka", SearchOption.TopDirectoryOnly);
        if (bundlePaths.Length == 0) throw new InvalidDataException("No .murchalka bundles were found.");
        var bundles = bundlePaths.Order(StringComparer.Ordinal).Select(ReadBundle).ToArray();
        if (bundles.Select(value => value.ModuleId + "@" + value.Version).Distinct(StringComparer.Ordinal).Count() != bundles.Length)
            throw new InvalidDataException("The bundle directory contains duplicate module identity and version pairs.");
        if (bundles.Where(value => !IsEffectivelyEmpty(value.Permissions)).GroupBy(value => value.ModuleId, StringComparer.Ordinal).Any(group => group.Count() > 1))
            throw new InvalidDataException("Multiple permission-bearing bundle versions for one module cannot share one generated grant file.");
        using var publisherKey = ReadPublicKey(publisherKeyPath);
        using var additionalPublisherKey = additionalPublisherKeyPath is null ? null : ReadPublicKey(additionalPublisherKeyPath);
        var publisherKeys = new Dictionary<string, ECDsa>(StringComparer.Ordinal) { [publisherKeyId] = publisherKey };
        if (additionalPublisherKeyId is not null && additionalPublisherKey is not null)
            publisherKeys.Add(additionalPublisherKeyId, additionalPublisherKey);
        if (bundles.Any(value => value.Publisher != Publisher || !publisherKeys.ContainsKey(value.PublisherKeyId)))
            throw new InvalidDataException("Every bundle must use the configured dev.murchalka publisher and an explicitly trusted publisher key identifier.");
        foreach (var bundle in bundles)
        {
            if (!publisherKeys[bundle.PublisherKeyId].VerifyData(bundle.SignedContent, bundle.Signature, HashAlgorithmName.SHA256, DSASignatureFormat.Rfc3279DerSequence))
                throw new CryptographicException($"Bundle signature for '{bundle.ModuleId}' is invalid for the configured publisher key.");
        }

        using var grantKey = ReadPrivateKey(grantPrivateKeyPath);
        Directory.CreateDirectory(outputPath);
        WriteAdminToken(Path.Combine(outputPath, "admin-token"));
        var grantsPath = Path.Combine(outputPath, "grants");
        Directory.CreateDirectory(grantsPath);

        var trust = new JsonObject
        {
            ["publishers"] = new JsonObject
            {
                [Publisher] = new JsonObject
                {
                    ["keys"] = new JsonObject(publisherKeys.Select(pair =>
                        KeyValuePair.Create<string, JsonNode?>(pair.Key, KeyDocument(pair.Value.ExportSubjectPublicKeyInfoPem()))))
                }
            },
            ["grantAuthorities"] = new JsonObject
            {
                [grantKeyId] = KeyDocument(grantKey.ExportSubjectPublicKeyInfoPem())
            }
        };
        WriteJson(Path.Combine(outputPath, "trusted-publishers.json"), trust);

        var issuedAt = DateTimeOffset.UtcNow;
        var written = 0;
        foreach (var bundle in bundles.Where(value => !IsEffectivelyEmpty(value.Permissions)))
        {
            var grant = CreateGrant(bundle, grantKeyId, grantKey, issuedAt);
            WriteJson(Path.Combine(grantsPath, bundle.ModuleId + ".json"), grant);
            written++;
        }

        Console.WriteLine($"Prepared trust for {bundles.Length} bundles and {written} explicit permission grants in '{outputPath}'.");
    }

    private static void WriteAdminToken(string path)
    {
        var token = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32))
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
        File.WriteAllText(path, token + Environment.NewLine);
        if (!OperatingSystem.IsWindows())
            File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite);
    }

    private static BundleDescriptor ReadBundle(string path)
    {
        using var archive = ZipFile.OpenRead(path);
        var manifest = ReadStructuredEntry(archive, "manifest/murchalka.module.yaml");
        var lockDocument = ReadJsonEntry(archive, "manifest/module.lock.json");
        var signature = ReadJsonEntry(archive, "signature/signature.json");
        var hashes = ReadJsonEntry(archive, "manifest/file-hashes.json");
        var metadata = RequiredObject(manifest, "metadata");
        var module = RequiredObject(lockDocument, "module");
        var signedContent = CreateBundleSignedContent(hashes);
        var bundleDigest = "sha256:" + Convert.ToHexStringLower(SHA256.HashData(signedContent));
        if (bundleDigest != RequiredString(module, "bundleDigest"))
            throw new InvalidDataException($"Bundle digest in '{Path.GetFileName(path)}' does not match its canonical signed content.");
        return new BundleDescriptor(
            RequiredString(metadata, "id"),
            RequiredString(metadata, "version"),
            RequiredString(metadata, "publisher"),
            RequiredString(signature, "keyId"),
            bundleDigest,
            manifest["permissions"]?.DeepClone() ?? new JsonObject(),
            signedContent,
            DecodeSignature(signature));
    }

    private static byte[] DecodeSignature(JsonObject signature)
    {
        try
        {
            return Convert.FromBase64String(RequiredString(signature, "signature"));
        }
        catch (FormatException exception)
        {
            throw new InvalidDataException("Bundle signature is not valid Base64.", exception);
        }
    }

    private static byte[] CreateBundleSignedContent(JsonObject hashesDocument)
    {
        if (hashesDocument["files"] is not JsonObject files) throw new InvalidDataException("Bundle file-hashes document has no files object.");
        var builder = new System.Text.StringBuilder("murchalka-bundle-v1\n");
        foreach (var pair in files.OrderBy(value => value.Key, StringComparer.Ordinal))
        {
            builder.Append(pair.Key).Append('\n');
            builder.Append(pair.Value?.GetValue<string>() ?? throw new InvalidDataException($"Hash for '{pair.Key}' is missing.")).Append('\n');
        }

        return System.Text.Encoding.UTF8.GetBytes(builder.ToString());
    }

    private static JsonObject CreateGrant(BundleDescriptor bundle, string keyId, ECDsa key, DateTimeOffset issuedAt)
    {
        var grantIdDigest = SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(bundle.ModuleId + "\n" + bundle.BundleDigest));
        var document = new JsonObject
        {
            ["apiVersion"] = "security.murchalka.dev/v1",
            ["kind"] = "ModulePermissionGrant",
            ["metadata"] = new JsonObject
            {
                ["grantId"] = "grant-" + Convert.ToHexStringLower(grantIdDigest)[..16],
                ["module"] = bundle.ModuleId,
                ["moduleVersionRange"] = bundle.Version,
                ["bundleDigest"] = bundle.BundleDigest,
                ["issuedAt"] = issuedAt.ToString("O", System.Globalization.CultureInfo.InvariantCulture),
                ["expiresAt"] = null,
                ["issuedBy"] = "local-deployment"
            },
            ["grant"] = CompactPermissions(bundle.Permissions),
            ["constraints"] = new JsonObject()
        };
        var signature = key.SignData(CanonicalJson.Serialize(document), HashAlgorithmName.SHA256, DSASignatureFormat.Rfc3279DerSequence);
        document["signature"] = new JsonObject
        {
            ["keyId"] = keyId,
            ["value"] = Convert.ToBase64String(signature)
        };
        return document;
    }

    private static JsonNode ReadStructuredEntry(ZipArchive archive, string entryPath)
    {
        var temporaryPath = Path.Combine(Path.GetTempPath(), "murchalka-manifest-" + Guid.NewGuid().ToString("N") + ".yaml");
        try
        {
            using (var source = RequiredEntry(archive, entryPath).Open())
            using (var target = new FileStream(temporaryPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                source.CopyTo(target);
            return StructuredDocument.Load(temporaryPath);
        }
        finally
        {
            File.Delete(temporaryPath);
        }
    }

    private static JsonObject ReadJsonEntry(ZipArchive archive, string entryPath)
    {
        using var stream = RequiredEntry(archive, entryPath).Open();
        return (JsonNode.Parse(stream) ?? throw new JsonException($"'{entryPath}' is empty.")).AsObject();
    }

    private static ZipArchiveEntry RequiredEntry(ZipArchive archive, string path) =>
        archive.GetEntry(path) ?? throw new InvalidDataException($"Bundle entry '{path}' is missing.");

    private static JsonObject RequiredObject(JsonNode node, string property) =>
        node[property] as JsonObject ?? throw new InvalidDataException($"Property '{property}' must be an object.");

    private static string RequiredString(JsonNode node, string property) =>
        node[property]?.GetValue<string>() is { Length: > 0 } value
            ? value
            : throw new InvalidDataException($"Property '{property}' must be a non-empty string.");

    private static JsonObject KeyDocument(string publicKeyPem) => new()
    {
        ["algorithm"] = Algorithm,
        ["publicKeyPem"] = publicKeyPem
    };

    private static ECDsa ReadPublicKey(string path)
    {
        var key = ECDsa.Create();
        try
        {
            key.ImportFromPem(File.ReadAllText(path));
            EnsureP256(key);
            return key;
        }
        catch
        {
            key.Dispose();
            throw;
        }
    }

    private static ECDsa ReadPrivateKey(string path)
    {
        var key = ECDsa.Create();
        try
        {
            key.ImportFromPem(File.ReadAllText(path));
            EnsureP256(key);
            if (key.ExportParameters(true).D is null) throw new CryptographicException("The permission-grant key must contain private key material.");
            return key;
        }
        catch
        {
            key.Dispose();
            throw;
        }
    }

    private static void EnsureP256(ECDsa key)
    {
        if (key.KeySize != 256) throw new CryptographicException("Only ECDSA P-256 keys are supported.");
    }

    private static void WriteJson(string path, JsonNode document)
    {
        var temporaryPath = path + ".tmp";
        File.WriteAllText(temporaryPath, document.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temporaryPath, path, overwrite: true);
    }

    private static bool IsEffectivelyEmpty(JsonNode? node) => node switch
    {
        null => true,
        JsonObject value => value.All(pair => IsEffectivelyEmpty(pair.Value)),
        JsonArray value => value.Count == 0,
        JsonValue value when value.TryGetValue<bool>(out var boolean) => !boolean,
        _ => false
    };

    private static JsonObject CompactPermissions(JsonNode permissions)
    {
        var result = new JsonObject();
        foreach (var pair in permissions.AsObject())
        {
            if (IsEffectivelyEmpty(pair.Value)) continue;
            result[pair.Key] = pair.Value?.DeepClone();
        }

        return result;
    }

    private static Dictionary<string, string> ParseOptions(string[] args)
    {
        if (args.Length == 0 || args.Length % 2 != 0)
            throw new ArgumentException("Usage: --bundles DIR --publisher-key FILE --publisher-key-id ID [--additional-publisher-key FILE --additional-publisher-key-id ID] --grant-private-key FILE [--grant-key-id ID] --output DIR");
        var options = new Dictionary<string, string>(StringComparer.Ordinal);
        for (var index = 0; index < args.Length; index += 2)
        {
            var name = args[index];
            if (!name.StartsWith("--", StringComparison.Ordinal) || !options.TryAdd(name[2..], args[index + 1]))
                throw new ArgumentException($"Invalid or duplicate option '{name}'.");
        }

        return options;
    }

    private static string Required(Dictionary<string, string> options, string key) =>
        options.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value)
            ? value
            : throw new ArgumentException($"Required option '--{key}' is missing.");

    private static void ValidateIdentifier(string value, string name)
    {
        if (value.Length is < 1 or > 128 || value.Any(character => !char.IsAsciiLetterOrDigit(character) && character is not '-' and not '_' and not '.'))
            throw new ArgumentException("Key identifiers may contain only ASCII letters, digits, '.', '-', and '_'.", name);
    }
}
