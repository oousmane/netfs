# Create an SSH connection description

Authenticate with an SSH agent, SSH configuration, or `identity_file`.
OpenSSH runs with `BatchMode=yes`, so it never prompts for a password;
`password` is stored for callers that authenticate another way, not for
netfs itself. Construction doesn't contact the server.

## Usage

``` r
ssh(host, user = NULL, port = 22, password = NULL, identity_file = NULL, ...)
```

## Arguments

- host:

  Server hostname.

- user:

  Optional login name.

- port:

  SSH port.

- password:

  Optional password to store in `keyring`, for callers that manage
  authentication themselves; prefer an SSH agent, SSH configuration, or
  `identity_file` for netfs's own use.

- identity_file:

  Optional private-key path.

- ...:

  Backend options.

## Value

A `netfs_ssh` connection.

## Details

On Unix, operations on one connection share a single OpenSSH
`ControlMaster` session instead of reconnecting on every call. Not
available on Windows, where OpenSSH's `ControlMaster` support is
unreliable; each call opens its own connection there instead.

## See also

Other connection constructors:
[`ftp()`](https://oousmane.github.io/netfs/reference/ftp.md),
[`s3()`](https://oousmane.github.io/netfs/reference/s3.md),
[`set_creds()`](https://oousmane.github.io/netfs/reference/set_creds.md),
[`smb()`](https://oousmane.github.io/netfs/reference/smb.md),
[`ssh_keygen()`](https://oousmane.github.io/netfs/reference/ssh_keygen.md),
[`webdav()`](https://oousmane.github.io/netfs/reference/webdav.md)

## Examples

``` r
ssh("server.example.org", user = "user")
#> <netfs_ssh>
#> host: server.example.org
#> user: user
#> port: 22
```
