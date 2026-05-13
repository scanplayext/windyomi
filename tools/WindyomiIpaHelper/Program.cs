using System.IO.Compression;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

var options = HelperOptions.Parse(args);
using var helper = new GitHubActionsHelper(options);

try
{
    Console.WriteLine("Windyomi IPA Helper");
    Console.WriteLine($"Repo: {options.Owner}/{options.Repo}");
    Console.WriteLine($"Workflow: {options.Workflow}");
    Console.WriteLine($"Ref: {options.Ref}");
    Console.WriteLine();

    var runId = options.DownloadOnlyRunId;
    if (runId is null)
    {
        await helper.DispatchWorkflow();
        Console.WriteLine("Build enviada a GitHub Actions.");
        runId = await helper.WaitForRun();
    }

    var outputDirectory = Path.GetFullPath(options.OutputDirectory);
    Directory.CreateDirectory(outputDirectory);
    var ipaPath = await helper.DownloadIpa(runId.Value, outputDirectory);

    Console.WriteLine();
    Console.WriteLine("IPA descargado:");
    Console.WriteLine(ipaPath);
}
catch (Exception ex)
{
    Console.ForegroundColor = ConsoleColor.Red;
    Console.WriteLine();
    Console.WriteLine("Error:");
    Console.WriteLine(ex.Message);
    Console.ResetColor();
    Environment.ExitCode = 1;
}

sealed class GitHubActionsHelper : IDisposable
{
    private readonly HelperOptions _options;
    private readonly HttpClient _http;
    private readonly DateTimeOffset _startedAt = DateTimeOffset.UtcNow;

    public GitHubActionsHelper(HelperOptions options)
    {
        _options = options;
        var token = options.Token;
        if (string.IsNullOrWhiteSpace(token))
        {
            Console.Write("GitHub token: ");
            token = ReadSecret();
            Console.WriteLine();
        }

        if (string.IsNullOrWhiteSpace(token))
        {
            throw new InvalidOperationException(
                "Necesitas un token de GitHub con permisos de Actions. Usa WINDYOMI_GITHUB_TOKEN o GH_TOKEN.");
        }

        _http = new HttpClient();
        _http.DefaultRequestHeaders.UserAgent.ParseAdd("WindyomiIpaHelper/1.0");
        _http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        _http.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        _http.DefaultRequestHeaders.Add("X-GitHub-Api-Version", "2022-11-28");
    }

    public async Task DispatchWorkflow()
    {
        var url = Api($"actions/workflows/{_options.Workflow}/dispatches");
        var json = JsonSerializer.Serialize(new { @ref = _options.Ref });
        using var content = new StringContent(json, Encoding.UTF8, "application/json");
        using var response = await _http.PostAsync(url, content);

        if ((int)response.StatusCode == 204)
        {
            return;
        }

        throw new InvalidOperationException(
            $"No se pudo lanzar el workflow ({(int)response.StatusCode}). {await response.Content.ReadAsStringAsync()}");
    }

    public async Task<long> WaitForRun()
    {
        Console.WriteLine("Esperando a que arranque la build...");
        GitHubRun? run = null;

        for (var attempt = 0; attempt < 90; attempt++)
        {
            var runs = await ListRuns();
            run = runs.FirstOrDefault(IsFreshRun);
            if (run is not null)
            {
                Console.WriteLine($"Run encontrado: {run.HtmlUrl}");
                break;
            }

            await Task.Delay(TimeSpan.FromSeconds(5));
        }

        if (run is null)
        {
            throw new TimeoutException("No he encontrado el run nuevo de GitHub Actions.");
        }

        while (!string.Equals(run.Status, "completed", StringComparison.OrdinalIgnoreCase))
        {
            Console.WriteLine($"Estado: {run.Status}. Siguiente revision en 15s...");
            await Task.Delay(TimeSpan.FromSeconds(15));
            run = await GetRun(run.Id);
        }

        Console.WriteLine($"Resultado: {run.Conclusion}");
        if (!string.Equals(run.Conclusion, "success", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException($"La build no termino bien: {run.HtmlUrl}");
        }

        return run.Id;
    }

    public async Task<string> DownloadIpa(long runId, string outputDirectory)
    {
        Console.WriteLine("Buscando artefacto IPA...");
        GitHubArtifact? artifact = null;

        for (var attempt = 0; attempt < 30; attempt++)
        {
            artifact = (await ListArtifacts(runId))
                .FirstOrDefault(item =>
                    item.Name.Contains("Windyomi", StringComparison.OrdinalIgnoreCase) &&
                    item.Name.Contains("ios", StringComparison.OrdinalIgnoreCase));

            if (artifact is not null)
            {
                break;
            }

            await Task.Delay(TimeSpan.FromSeconds(5));
        }

        if (artifact is null)
        {
            throw new InvalidOperationException("No he encontrado el artefacto Windyomi-unsigned-ios.");
        }

        var tempZip = Path.Combine(Path.GetTempPath(), $"windyomi-ipa-{runId}.zip");
        await using (var stream = await _http.GetStreamAsync(artifact.ArchiveDownloadUrl))
        await using (var file = File.Create(tempZip))
        {
            await stream.CopyToAsync(file);
        }

        var extractDir = Path.Combine(Path.GetTempPath(), $"windyomi-ipa-{runId}");
        if (Directory.Exists(extractDir))
        {
            Directory.Delete(extractDir, recursive: true);
        }
        ZipFile.ExtractToDirectory(tempZip, extractDir);

        var ipa = Directory.EnumerateFiles(extractDir, "*.ipa", SearchOption.AllDirectories)
            .FirstOrDefault();

        if (ipa is null)
        {
            throw new InvalidOperationException("El artefacto se descargo, pero no contenia ningun .ipa.");
        }

        var target = Path.Combine(outputDirectory, Path.GetFileName(ipa));
        if (File.Exists(target))
        {
            var name = Path.GetFileNameWithoutExtension(ipa);
            target = Path.Combine(outputDirectory, $"{name}-{runId}.ipa");
        }

        File.Copy(ipa, target, overwrite: false);
        return target;
    }

    private bool IsFreshRun(GitHubRun run)
    {
        return string.Equals(run.Event, "workflow_dispatch", StringComparison.OrdinalIgnoreCase) &&
               string.Equals(run.HeadBranch, _options.Ref, StringComparison.OrdinalIgnoreCase) &&
               run.CreatedAt >= _startedAt.AddMinutes(-2);
    }

    private async Task<List<GitHubRun>> ListRuns()
    {
        var url = Api($"actions/workflows/{_options.Workflow}/runs?branch={Uri.EscapeDataString(_options.Ref)}&event=workflow_dispatch&per_page=10");
        using var doc = await GetJson(url);
        var runs = doc.RootElement.GetProperty("workflow_runs");
        return runs.EnumerateArray().Select(GitHubRun.FromJson).ToList();
    }

    private async Task<GitHubRun> GetRun(long id)
    {
        using var doc = await GetJson(Api($"actions/runs/{id}"));
        return GitHubRun.FromJson(doc.RootElement);
    }

    private async Task<List<GitHubArtifact>> ListArtifacts(long runId)
    {
        using var doc = await GetJson(Api($"actions/runs/{runId}/artifacts"));
        var artifacts = doc.RootElement.GetProperty("artifacts");
        return artifacts.EnumerateArray().Select(GitHubArtifact.FromJson).ToList();
    }

    private async Task<JsonDocument> GetJson(string url)
    {
        using var response = await _http.GetAsync(url);
        var body = await response.Content.ReadAsStringAsync();
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"GitHub API error {(int)response.StatusCode}: {body}");
        }
        return JsonDocument.Parse(body);
    }

    private string Api(string path)
    {
        return $"https://api.github.com/repos/{_options.Owner}/{_options.Repo}/{path}";
    }

    public void Dispose() => _http.Dispose();

    private static string ReadSecret()
    {
        var builder = new StringBuilder();
        ConsoleKeyInfo key;
        while ((key = Console.ReadKey(intercept: true)).Key != ConsoleKey.Enter)
        {
            if (key.Key == ConsoleKey.Backspace)
            {
                if (builder.Length > 0)
                {
                    builder.Length--;
                    Console.Write("\b \b");
                }
                continue;
            }

            builder.Append(key.KeyChar);
            Console.Write("*");
        }

        return builder.ToString();
    }
}

sealed record HelperOptions(
    string Owner,
    string Repo,
    string Workflow,
    string Ref,
    string OutputDirectory,
    string? Token,
    long? DownloadOnlyRunId)
{
    public static HelperOptions Parse(string[] args)
    {
        var owner = "scanplayext";
        var repo = "windyomi";
        var workflow = "build_ios_unsigned.yml";
        var branchRef = "main";
        var output = "dist";
        long? downloadOnly = null;

        for (var i = 0; i < args.Length; i++)
        {
            var arg = args[i];
            var value = i + 1 < args.Length ? args[i + 1] : null;

            switch (arg)
            {
                case "--repo" when value is not null:
                    var parts = value.Split('/', 2);
                    if (parts.Length != 2)
                    {
                        throw new ArgumentException("--repo debe tener formato owner/repo.");
                    }
                    owner = parts[0];
                    repo = parts[1];
                    i++;
                    break;
                case "--workflow" when value is not null:
                    workflow = value;
                    i++;
                    break;
                case "--ref" when value is not null:
                    branchRef = value;
                    i++;
                    break;
                case "--out" when value is not null:
                    output = value;
                    i++;
                    break;
                case "--download-only" when value is not null:
                    downloadOnly = long.Parse(value);
                    i++;
                    break;
                case "--help":
                case "-h":
                    PrintHelp();
                    Environment.Exit(0);
                    break;
            }
        }

        return new HelperOptions(
            owner,
            repo,
            workflow,
            branchRef,
            output,
            Environment.GetEnvironmentVariable("WINDYOMI_GITHUB_TOKEN") ??
            Environment.GetEnvironmentVariable("GH_TOKEN") ??
            Environment.GetEnvironmentVariable("GITHUB_TOKEN"),
            downloadOnly);
    }

    private static void PrintHelp()
    {
        Console.WriteLine("""
WindyomiIpaHelper

Uso:
  WindyomiIpaHelper.exe
  WindyomiIpaHelper.exe --out C:\IPA
  WindyomiIpaHelper.exe --download-only RUN_ID

Variables:
  WINDYOMI_GITHUB_TOKEN, GH_TOKEN o GITHUB_TOKEN

Opciones:
  --repo owner/repo
  --workflow build_ios_unsigned.yml
  --ref main
  --out carpeta
  --download-only run_id
""");
    }
}

sealed record GitHubRun(
    long Id,
    string Status,
    string? Conclusion,
    string Event,
    string HeadBranch,
    string HtmlUrl,
    DateTimeOffset CreatedAt)
{
    public static GitHubRun FromJson(JsonElement json)
    {
        return new GitHubRun(
            json.GetProperty("id").GetInt64(),
            json.GetProperty("status").GetString() ?? "",
            json.GetProperty("conclusion").GetString(),
            json.GetProperty("event").GetString() ?? "",
            json.GetProperty("head_branch").GetString() ?? "",
            json.GetProperty("html_url").GetString() ?? "",
            json.GetProperty("created_at").GetDateTimeOffset());
    }
}

sealed record GitHubArtifact(string Name, string ArchiveDownloadUrl)
{
    public static GitHubArtifact FromJson(JsonElement json)
    {
        return new GitHubArtifact(
            json.GetProperty("name").GetString() ?? "",
            json.GetProperty("archive_download_url").GetString() ?? "");
    }
}
