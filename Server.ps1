param(
    [string]$Address = "localhost",
    [int]$Port = 8080
)

class ItemStore {
    [System.Collections.Generic.List[object]]$Items

    ItemStore() {
        $this.Items = [System.Collections.Generic.List[object]]::new()
    }

    [object[]] GetAll() {
        return $this.Items.ToArray()
    }

    [object] GetById([Guid]$Id) {
        foreach ($item in $this.Items) {
            if ([Guid]$item.id -eq $Id) {
                return $item
            }
        }

        return $null
    }

    [void] Add([object]$Item) {
        $this.Items.Add($Item)
    }

    [bool] RemoveById([Guid]$Id) {
        for ($index = 0; $index -lt $this.Items.Count; $index++) {
            if ([Guid]$this.Items[$index].id -eq $Id) {
                $this.Items.RemoveAt($index)
                return $true
            }
        }

        return $false
    }

    [void] Clear() {
        $this.Items.Clear()
    }
}

class Server {
    [string]$Address
    [ItemStore]$ItemStore

    Server() {
        $this.Address = "localhost"
        $this.ItemStore = [ItemStore]::new()
    }

    [void] WriteJsonResponse(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [object]$Payload
    ) {
        $json = if ($null -eq $Payload) { "null" } else { $Payload | ConvertTo-Json -Depth 10 -Compress }
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)

        $Response.StatusCode = $StatusCode
        $Response.ContentType = "application/json; charset=utf-8"
        $Response.ContentLength64 = $buffer.Length
        $Response.OutputStream.Write($buffer, 0, $buffer.Length)
        $Response.OutputStream.Close()
    }

    [void] WriteJsonError(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [string]$Message
    ) {
        $this.WriteJsonResponse($Response, $StatusCode, @{ error = $Message })
    }

    [string] ReadJsonRequestBody([System.Net.HttpListenerRequest]$Request) {
        $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
        $reader = [System.IO.StreamReader]::new($Request.InputStream, $utf8)
        try {
            return $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }

    [object] TestItemPayload(
        [object]$Payload,
        [System.Net.HttpListenerResponse]$Response
    ) {
        if (($Payload.a -isnot [string]) -or [string]::IsNullOrWhiteSpace($Payload.a)) {
            $this.WriteJsonError($Response, 400, "Field 'a' must be a non-empty string.")
            return $false
        }

        if (($Payload.b -isnot [string]) -or [string]::IsNullOrWhiteSpace($Payload.b)) {
            $this.WriteJsonError($Response, 400, "Field 'b' must be a non-empty string.")
            return $false
        }

        if (($Payload.c -isnot [string]) -or [string]::IsNullOrWhiteSpace($Payload.c)) {
            $this.WriteJsonError($Response, 400, "Field 'c' must be a non-empty string.")
            return $false
        }

        if (($Payload.d -isnot [string]) -or [string]::IsNullOrWhiteSpace($Payload.d)) {
            $this.WriteJsonError($Response, 400, "Field 'd' must be a non-empty string.")
            return $false
        }

        return [pscustomobject]@{
            a = $Payload.a.Trim()
            b = $Payload.b.Trim()
            c = $Payload.c.Trim()
            d = $Payload.d.Trim()
        }
    }

    [void] GetItemsEndpoint([System.Net.HttpListenerResponse]$Response) {
        $this.WriteJsonResponse($Response, 200, @{ items = @($this.ItemStore.GetAll()) })
    }

    [void] GetItemEndpoint(
        [string]$ItemId,
        [System.Net.HttpListenerResponse]$Response
    ) {
        $id = [Guid]::Empty
        if (-not [Guid]::TryParse($ItemId, [ref]$id)) {
            $this.WriteJsonError($Response, 400, "Item id must be a UUID.")
            return
        }

        $item = $this.ItemStore.GetById($id)
        if ($null -eq $item) {
            $this.WriteJsonError($Response, 404, "Item not found.")
            return
        }

        $this.WriteJsonResponse($Response, 200, $item)
    }

    [void] NewItemEndpoint(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response
    ) {
        $body = $null
        try {
            $body = $this.ReadJsonRequestBody($Request)
        }
        catch [System.Text.DecoderFallbackException] {
            $this.WriteJsonError($Response, 400, "Request body must be valid UTF-8.")
            return
        }

        if ([string]::IsNullOrWhiteSpace($body)) {
            $this.WriteJsonError($Response, 400, "Request body is required.")
            return
        }

        try {
            $payload = $body | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            $this.WriteJsonError($Response, 400, "Invalid JSON payload.")
            return
        }

        $validatedItem = $this.TestItemPayload($payload, $Response)
        if ($validatedItem -is [bool]) {
            return
        }

        $item = [pscustomobject]@{
            id = [Guid]::NewGuid().ToString()
            a = $validatedItem.a
            b = $validatedItem.b
            c = $validatedItem.c
            d = $validatedItem.d
        }

        $this.ItemStore.Add($item)
        $this.WriteJsonResponse($Response, 201, $item)
    }

    [void] RemoveItemEndpoint(
        [string]$ItemId,
        [System.Net.HttpListenerResponse]$Response
    ) {
        $id = [Guid]::Empty
        if (-not [Guid]::TryParse($ItemId, [ref]$id)) {
            $this.WriteJsonError($Response, 400, "Item id must be a UUID.")
            return
        }

        if (-not $this.ItemStore.RemoveById($id)) {
            $this.WriteJsonError($Response, 404, "Item not found.")
            return
        }

        $Response.StatusCode = 204
        $Response.ContentLength64 = 0
        $Response.OutputStream.Close()
    }

    [void] ClearItemsEndpoint([System.Net.HttpListenerResponse]$Response) {
        $this.ItemStore.Clear()
        $Response.StatusCode = 204
        $Response.ContentLength64 = 0
        $Response.OutputStream.Close()
    }

    [void] InvokeEndpoint([System.Net.HttpListenerContext]$Context) {
        $request = $Context.Request
        $response = $Context.Response
        $rawPath = $request.Url.AbsolutePath
        $path = if ([string]::IsNullOrEmpty($rawPath)) { "/" } else { $rawPath }

        if ($request.HttpMethod -eq "GET" -and ($path -eq "/" -or $path -eq "/items")) {
            $this.GetItemsEndpoint($response)
            return
        }

        if ($request.HttpMethod -eq "GET" -and $path -match '^/items/([^/]+)$') {
            $this.GetItemEndpoint($Matches[1], $response)
            return
        }

        if ($request.HttpMethod -eq "POST" -and ($path -eq "/" -or $path -eq "/items")) {
            $this.NewItemEndpoint($request, $response)
            return
        }

        if ($request.HttpMethod -eq "DELETE" -and $path -eq "/items") {
            $this.ClearItemsEndpoint($response)
            return
        }

        if ($request.HttpMethod -eq "DELETE" -and $path -match '^/items/([^/]+)$') {
            $this.RemoveItemEndpoint($Matches[1], $response)
            return
        }

        $this.WriteJsonError($response, 404, "Endpoint not found.")
    }

    [void] InvokeRequest([System.Net.HttpListenerContext]$Context) {
        try {
            $this.InvokeEndpoint($Context)
        }
        catch {
            $this.WriteJsonError($Context.Response, 500, "Internal server error.")
        }
        finally {
            if ($Context.Response.OutputStream.CanWrite) {
                $Context.Response.OutputStream.Close()
            }
        }
    }

    [void] Start([int]$Port) {
        $listener = [System.Net.HttpListener]::new()
        $url = "http://$($this.Address):$Port/"
        $listener.Prefixes.Add($url)
        $listener.Start()

        Write-Host "Listening on $url"
        Write-Host "Press Q to stop the server."

        try {
            while ($true) {
                $contextResult = $listener.BeginGetContext($null, $null)
                $waitHandle = $contextResult.AsyncWaitHandle
                $shutdownRequested = $false

                while (-not $waitHandle.WaitOne(100)) {
                    if (-not [Console]::IsInputRedirected -and [Console]::KeyAvailable) {
                        $key = [Console]::ReadKey($true)
                        if ($key.Key -eq [ConsoleKey]::Q) {
                            $shutdownRequested = $true
                            $listener.Stop()
                            break
                        }
                    }
                }

                $waitHandle.Close()

                if ($shutdownRequested) {
                    try { $null = $listener.EndGetContext($contextResult) }
                    catch [System.Net.HttpListenerException] {}
                    catch [System.ObjectDisposedException] {}
                    break
                }

                $context = $listener.EndGetContext($contextResult)
                $this.InvokeRequest($context)
            }
        }
        finally {
            $listener.Stop()
            $listener.Close()
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $server = [Server]::new()
    $server.Address = $Address
    $server.Start($Port)
}
