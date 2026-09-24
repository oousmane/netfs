# Create an SMB connection description

SMB support is provided by the smbclientr package: native UNC access on
Windows, and Samba's `smbclient` (`brew install samba`) on macOS and
Linux. See
[`smbclientr::smb_connection()`](https://rdrr.io/pkg/smbclientr/man/smb_connection.html)
for backend details.

## Usage

``` r
smb(host, share, user = NULL, password = NULL, domain = NULL, ...)
```

## Arguments

- host:

  SMB server hostname.

- share:

  Share name, separate from operation paths.

- user:

  Optional login name.

- password:

  Optional password. When supplied, it is written to the selected
  `keyring` credential store and is not retained in the connection.

- domain:

  Optional Windows domain.

- ...:

  Additional arguments passed to
  [`smbclientr::smb_connection()`](https://rdrr.io/pkg/smbclientr/man/smb_connection.html)
  (for example `send_buffer`).

## Value

A `netfs_smb` connection. This object is also a valid smbclientr
`smb_connection` - the same fields (`host`, `share`, `user`, `domain`)
are not duplicated between the two packages.

## See also

Other connection constructors:
[`ftp()`](https://oousmane.github.io/netfs/reference/ftp.md),
[`s3()`](https://oousmane.github.io/netfs/reference/s3.md),
[`set_creds()`](https://oousmane.github.io/netfs/reference/set_creds.md),
[`ssh()`](https://oousmane.github.io/netfs/reference/ssh.md),
[`ssh_keygen()`](https://oousmane.github.io/netfs/reference/ssh_keygen.md),
[`webdav()`](https://oousmane.github.io/netfs/reference/webdav.md)

## Examples

``` r
if (FALSE) { # \dontrun{
smb("fileserver", "DATA")
} # }
```
