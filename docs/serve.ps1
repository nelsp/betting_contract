# Minimal static file server for Bet Desk. Serves this folder at http://localhost:8000/
# MetaMask does not inject into file:// pages, so the UI must be served over http.
param([int]$Port = 8000)

$root = $PSScriptRoot
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Bet Desk running at http://localhost:$Port/  (Ctrl+C to stop)"

$types = @{ '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript'; '.css' = 'text/css'; '.json' = 'application/json'; '.ico' = 'image/x-icon' }

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $path = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath).TrimStart('/')
        if ($path -eq '') { $path = 'index.html' }
        $file = [IO.Path]::GetFullPath((Join-Path $root $path))
        $res = $ctx.Response
        if ($file.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path $file -PathType Leaf)) {
            $bytes = [IO.File]::ReadAllBytes($file)
            $ext = [IO.Path]::GetExtension($file).ToLower()
            $res.ContentType = if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' }
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $res.StatusCode = 404
        }
        $res.Close()
    }
} finally {
    $listener.Stop()
}
