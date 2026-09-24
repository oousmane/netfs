# Create a WebDAV connection description

WebDAV is identified by a single base URL rather than a separate host
and share/port, since that URL commonly includes a server-specific path
prefix (for example a per-user DAV root on a file-sync server). Support
is provided by the webdav package. Construction doesn't contact the
server.

## Usage

``` r
webdav(url, user = NULL, password = NULL, ...)
```

## Arguments

- url:

  The server's base WebDAV URL, e.g.
  `"https://cloud.example.org/remote.php/dav/files/alice/"`.

- user:

  Optional login name.

- password:

  Optional password. When supplied, it is written to the selected
  `keyring` credential store and is not retained in the connection.

- ...:

  Backend options.

## Value

A `netfs_webdav` connection.

## See also

Other connection constructors:
[`ftp()`](https://oousmane.github.io/netfs/reference/ftp.md),
[`s3()`](https://oousmane.github.io/netfs/reference/s3.md),
[`set_creds()`](https://oousmane.github.io/netfs/reference/set_creds.md),
[`smb()`](https://oousmane.github.io/netfs/reference/smb.md),
[`ssh()`](https://oousmane.github.io/netfs/reference/ssh.md),
[`ssh_keygen()`](https://oousmane.github.io/netfs/reference/ssh_keygen.md)

## Examples

``` r
if (FALSE) { # \dontrun{
webdav("https://cloud.example.org/remote.php/dav/files/alice/", user = "alice")
} # }
```
