# netfs

[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)

`netfs` extends [`fs`](https://fs.r-lib.org)'s filesystem interface to remote
connections. Every function keeps `fs`'s names, arguments, and return types;
adding `con = <connection>` sends the same call to an FTP, SSH, SMB,
WebDAV, or S3 server instead of the local disk. Calls without `con`
delegate directly to `fs`.

## Installation

```r
install.packages(".", repos = NULL, type = "source")
```

## Usage

```r
library(netfs)

dir_ls("data")                                        # local, as usual

server <- ssh("server.example.org", user = "user")
dir_ls("/data", con = server)
file_download("/data/input.csv", local = "input.csv", con = server)
```

`ftp()`, `ssh()`, and `smb()` describe a connection without contacting the
server; a connection never prints its password. Substitute one for another
without changing the rest of the code:

```r
server <- smb("fileserver", "DATA")
dir_ls("/reports", con = server)
dir_ls(server)                       # shorthand for the connection's root
```

Remote paths work with or without a leading slash:

```r
dir_ls("/reports", con = server)
dir_ls("reports", con = server)
```

### Transfers

A destination that's an existing directory, or ends in `/`, appends the
source's basename automatically:

```r
file_upload("report.pdf", "/archive/", con = server)
file_download("/reports/result.csv", "downloads/", con = server)
```

Uploads refuse to replace an existing remote file unless `overwrite = TRUE`.
Downloads with `overwrite = FALSE` (the default) keep an existing file and
write to a numbered name instead, e.g. `result-1.csv`.

`file_transfer()` moves a file between two different connections through a
local staging copy - not a direct server-to-server transfer:

```r
file_transfer(
  "/incoming/report.csv", "/archive/",
  from = ftp("ftp.example.org", user = "analyst"),
  to = smb("fileserver", "DATA", user = "analyst")
)
```

### SSH keys

`ssh_keygen()` generates an identity file and prints the command to register
it on the server; it never contacts the server itself:

```r
key <- ssh_keygen("server.example.org", user = "user")
#> Generated identity file: ~/.ssh/id_ed25519_user_server.example.org
#> Register it on the server by running:
#>   ssh-copy-id -i ~/.ssh/id_ed25519_user_server.example.org.pub user@server.example.org
server <- ssh("server.example.org", user = "user", identity_file = key)
```

## Credentials

Passwords are stored in the operating system's credential store, never in
source code or in the connection object itself:

```r
server <- ftp("ftp.example.org", user = "analyst")
set_creds(server)          # prompts for the password without echoing it
get_creds(server)          # <hidden>
delete_creds(server)
```

Select a named keyring by setting `NETFS_KEYRING` in `.Renviron` - never put
the password itself there. A `password =` argument to a connection
constructor is stored through `keyring` immediately and not retained on the
connection object.

## Backends

| Backend | Engine | Package | Requires |
|---|---|---|---|
| Local | libuv | `fs` | Nothing extra |
| FTP / FTPS | libcurl | `curl` | Nothing extra |
| SSH / SFTP | openssh | *(system)* | The `ssh` and `scp` executables |
| SMB | smbclient | [`smbclientr`](https://github.com/oousmane/smbclientr) | The `smbclientr` package (optional) |
| WebDAV | `httr2` | `webdav` | The `webdav` package (optional) |
| S3 | `paws` | `s3fs` | The `s3fs` package (optional) |

`netfs_capabilities()` reports these same `engine` and `package` values, plus
whether each is actually available on the current machine.

SMB is handled entirely by `smbclientr`: Samba's `smbclient` on Linux and
macOS (`brew install samba`), native UNC access on Windows. WebDAV is
handled entirely by the `webdav` package, itself built on `httr2` alone.
S3 is handled entirely by `s3fs`, built on `paws` alone. None of the three
need an external binary; all three translate their own errors into
`netfs`'s condition classes and otherwise stay out of the protocol.

```r
server <- webdav("https://cloud.example.org/remote.php/dav/files/alice/", user = "alice")
dir_ls("/reports", con = server)

bucket <- s3("my-bucket", region_name = "us-east-1")
dir_ls("/reports", con = bucket)
```

A WebDAV connection is identified by a single base URL rather than a
separate host and port, since that URL commonly carries a server-specific
path prefix (a per-user DAV root, for instance). An S3 connection is
scoped to one bucket, the same way `smb()` is scoped to one share - paths
are always relative to that bucket's own key namespace. Neither WebDAV nor
S3 has a server-side rename, so `file_move()` on either is a copy followed
by deleting the source - not atomic: if the delete fails, both copies are
left behind rather than neither.

```r
netfs_capabilities()          # client availability, this machine
netfs_capabilities(server)    # operations this connection supports
```

## API coverage

`netfs` covers `fs`'s full remote-relevant API: alongside `dir_ls()`,
`file_copy()`, `file_move()`, `file_info()`, and the operations above, it
also provides `dir_info()`, `dir_map()`, `dir_walk()`, `dir_tree()`,
`dir_copy()`, `file_size()`, `file_create()`, `is_file()`, `is_dir()`,
`is_link()`, `is_file_empty()`, `is_dir_empty()`, `file_access()`,
`file_chmod()`, `file_chown()`, `file_touch()`, `link_create()`,
`link_path()`, `link_copy()`, and `link_delete()`. `dir_ls()` and
`dir_info()` take a `recurse` argument.

A few `fs` functions have no remote counterpart, because they never touch a
connection's filesystem in the first place: `fs::path_*()` functions are
plain string manipulation and work unchanged on a remote path; `file_temp()`
and `group_ids()`/`user_ids()` refer to the local machine. Call `fs::`
directly for these.

Permissions, ownership, arbitrary timestamps, and symlinks
(`file_chmod()`, `file_chown()`, `file_touch()` with an explicit timestamp,
`file_access()`'s read/write/execute modes, and every `link_*()` function)
work only over SSH, which is the one backend with a real remote shell behind
it. FTP, SMB, WebDAV, and S3 have no consistent equivalent and raise
`netfs_unsupported`. `file_show()` always raises it too, for any remote
connection - it opens a local viewer, which has no meaning for a path that
isn't on this machine.

## Limitations

- Server-side `file_copy()` isn't available over FTP, which has no copy
  command in its protocol; it fails with `netfs_unsupported`. SSH, SMB,
  WebDAV, and S3 all support it natively. `dir_copy()` works everywhere
  regardless: on FTP, each file is copied through a local staging download
  and upload.
- S3 has no atomic "fail if not empty" primitive the way `rmdir` or FTP's
  `RMD` do - `dir_delete()` without `recurse = TRUE` still refuses a
  non-empty "directory" there, but by checking with an extra listing
  first, not a single native call.
- SSH authentication never places a password on the command line; use an
  agent, SSH configuration, or an identity file. Operations on one
  connection share a single OpenSSH `ControlMaster` session on Unix, so
  repeated calls reuse the handshake instead of reconnecting each time
  (not available on Windows).
- `file_touch()` with an explicit timestamp requires GNU `touch` on the
  remote; BSD/macOS SSH servers aren't currently supported for that case.
- Unit tests run against mocked transports and don't require a live server.

Remote errors inherit from `netfs_error`, with subclasses for authentication,
missing paths, permissions, timeouts, unavailable backends, and unsupported
operations.
