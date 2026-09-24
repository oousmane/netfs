# Generate an SSH identity file for a connection

Creates a new ed25519 keypair under `~/.ssh` (reusing one already at the
target `path` unless `overwrite = TRUE`) and prints the `ssh-copy-id`
command that registers the public key on the server. Registering the key
is a one-time step you run yourself; this function never contacts the
server.

## Usage

``` r
ssh_keygen(host, user = NULL, port = 22, path = NULL, overwrite = FALSE)
```

## Arguments

- host, user, port:

  As passed to
  [`ssh()`](https://oousmane.github.io/netfs/reference/ssh.md); used to
  build a descriptive key filename and the suggested `ssh-copy-id`
  command.

- path:

  Optional private-key path. Defaults to
  `~/.ssh/id_ed25519_<user>_<host>` (or `~/.ssh/id_ed25519_<host>` when
  `user` is `NULL`), with characters unsafe for a filename replaced by
  `_`.

- overwrite:

  Regenerate an existing key at `path`? Default `FALSE` reuses it as-is.

## Value

The identity file path, invisibly. Pass it as
`ssh(..., identity_file = )`.

## See also

Other connection constructors:
[`ftp()`](https://oousmane.github.io/netfs/reference/ftp.md),
[`s3()`](https://oousmane.github.io/netfs/reference/s3.md),
[`set_creds()`](https://oousmane.github.io/netfs/reference/set_creds.md),
[`smb()`](https://oousmane.github.io/netfs/reference/smb.md),
[`ssh()`](https://oousmane.github.io/netfs/reference/ssh.md),
[`webdav()`](https://oousmane.github.io/netfs/reference/webdav.md)

## Examples

``` r
if (FALSE) { # \dontrun{
key <- ssh_keygen("server.example.org", user = "alice")
con <- ssh("server.example.org", user = "alice", identity_file = key)
} # }
```
