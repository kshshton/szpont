# Items API

A small HTTP JSON API implemented with Windows PowerShell and `HttpListener`.
Items are held in memory while the server is running; they are cleared when the
server stops.

## Requirements

- Windows PowerShell 5.1 or later

## Run the server

From this directory, run:

```powershell
.\Server.ps1
```

The server listens at `http://localhost:8080/` by default. Choose a different
address with the `-Address` parameter and a different port with the `-Port`
parameter:

```powershell
.\Server.ps1 -Port 9000
.\Server.ps1 -Address 127.0.0.1 -Port 9000
```

`-Address` defaults to `localhost`; it is used as the host in the HTTP listener
URL.

Press `Q` in the server's terminal to stop it.

## API

### List items

`GET /` or `GET /items`

Returns all items:

```powershell
$response = Invoke-RestMethod -Method Get -Uri "http://localhost:8080/items"
$response.items | Select-Object id, a, b, c, d
```

The response is JSON in this shape:

```json
{
  "items": [
    {
      "id": "UUID",
      "a": "something",
      "b": "something",
      "c": "something",
      "d": "something"
    }
  ]
}
```

### Get an item

`GET /items/{id}`

Returns the matching item as JSON. A malformed UUID returns `400 Bad Request`;
a valid UUID that does not match an existing item returns `404 Not Found`.

```powershell
$item = Invoke-RestMethod `
    -Method Get `
    -Uri "http://localhost:8080/items/$($item.id)"
```

### Create an item

`POST /` or `POST /items`

Send a JSON body with the following fields:

```json
{
  "a": "something",
  "b": "something",
  "c": "something",
  "d": "something"
}
```

The request and returned item use `a` for ssid, `b` for password, `c` for name,
and `d` for cords. All four fields must be non-empty strings. The API returns `201 Created` and the created
item, including a randomly generated UUID `id`. Request and response JSON use
UTF-8.

Example using PowerShell:

```powershell
$body = @{
    a = "something"
    b = "something"
    c = "something"
    d = "something"
} | ConvertTo-Json

$item = Invoke-RestMethod `
    -Method Post `
    -Uri "http://localhost:8080/items" `
    -ContentType "application/json; charset=utf-8" `
    -Body $body

$item.id
```

### Delete an item

`DELETE /items/{id}`

Replace `{id}` with the UUID returned when the item was created. A successful
deletion returns `204 No Content`. A malformed UUID returns `400 Bad Request`;
a valid UUID that does not match an existing item returns `404 Not Found`.

```powershell
Invoke-WebRequest `
    -UseBasicParsing `
    -Method Delete `
    -Uri "http://localhost:8080/items/$($item.id)"
```

### Delete all items

`DELETE /items`

Removes every item currently held by the server and returns `204 No Content`.

```powershell
Invoke-WebRequest `
    -UseBasicParsing `
    -Method Delete `
    -Uri "http://localhost:8080/items"
```

## Errors

Errors are returned as JSON with an `error` field. Invalid request bodies or
fields return `400 Bad Request`; unmatched routes and missing items return
`404 Not Found`.
