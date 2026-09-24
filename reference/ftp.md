# Create an FTP or FTPS connection description

Construction validates settings but does not contact the server.

## Usage

``` r
ftp(host, user = NULL, password = NULL, port = 21, tls = FALSE, ...)
```

## Arguments

- host:

  Server hostname, with or without an FTP scheme.

- user:

  Optional login name.

- password:

  Optional password. When supplied, it is written to the selected
  `keyring` credential store and is not retained in the connection.

- port:

  Server port.

- tls:

  Use explicit TLS through libcurl.

- ...:

  Backend options retained for future requests.

## Value

A `netfs_ftp` connection.

## See also

Other connection constructors:
[`s3()`](https://oousmane.github.io/netfs/reference/s3.md),
[`set_creds()`](https://oousmane.github.io/netfs/reference/set_creds.md),
[`smb()`](https://oousmane.github.io/netfs/reference/smb.md),
[`ssh()`](https://oousmane.github.io/netfs/reference/ssh.md),
[`ssh_keygen()`](https://oousmane.github.io/netfs/reference/ssh_keygen.md),
[`webdav()`](https://oousmane.github.io/netfs/reference/webdav.md)

## Examples

``` r
ftp("ftp.example.org")
#> <netfs_ftp>
#> host: ftp.example.org
#> port: 21
#> tls: false
```
