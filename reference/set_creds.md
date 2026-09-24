# Manage credentials for a remote connection

Credentials are stored in the operating system credential store through
`keyring`. The connection object contains no password. Set
`NETFS_KEYRING` in `.Renviron` to select a named keyring; leave it unset
to use the system default keyring. Never place the password itself in
`.Renviron`.

## Usage

``` r
set_creds(con, password = NULL, keyring = NULL)

get_creds(con, keyring = NULL)

delete_creds(con, keyring = NULL)
```

## Arguments

- con:

  A connection created by
  [`ftp()`](https://oousmane.github.io/netfs/reference/ftp.md),
  [`ssh()`](https://oousmane.github.io/netfs/reference/ssh.md), or
  [`smb()`](https://oousmane.github.io/netfs/reference/smb.md).

- password:

  Optional password. When `NULL`,
  [`keyring::key_set()`](https://keyring.r-lib.org/reference/key_get.html)
  requests it interactively without echoing it.

- keyring:

  Optional keyring name. By default, uses `NETFS_KEYRING` and then the
  system default keyring.

## Value

`set_creds()` and `delete_creds()` return `con` invisibly. `get_creds()`
returns a hidden `netfs_creds` object.

## See also

Other connection constructors:
[`ftp()`](https://oousmane.github.io/netfs/reference/ftp.md),
[`s3()`](https://oousmane.github.io/netfs/reference/s3.md),
[`smb()`](https://oousmane.github.io/netfs/reference/smb.md),
[`ssh()`](https://oousmane.github.io/netfs/reference/ssh.md),
[`ssh_keygen()`](https://oousmane.github.io/netfs/reference/ssh_keygen.md),
[`webdav()`](https://oousmane.github.io/netfs/reference/webdav.md)

## Examples

``` r
if (FALSE) { # \dontrun{
con <- ftp("ftp.example.org", user = "analyst")
set_creds(con)
get_creds(con)
delete_creds(con)
} # }
```
