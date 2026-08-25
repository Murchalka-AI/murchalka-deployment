namespace Murchalka.Deployment.Tests;

internal static class RepositoryRootLocator
{
    public static string Find()
    {
        var current = new DirectoryInfo(AppContext.BaseDirectory);
        while (current is not null)
        {
            if (Directory.Exists(Path.Combine(current.FullName, "profiles"))) return current.FullName;
            current = current.Parent;
        }

        throw new DirectoryNotFoundException();
    }
}

