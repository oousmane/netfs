# netfs

[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)

`netfs` provides `fs`-style filesystem operations for local files and remote
FTP, SSH, and SMB connections. Local operations delegate directly to `fs`.

## Installation

Install the package from its source directory:

```r
install.packages(".", repos = NULL, type = "source")
```

## Usage

```r
library(netfs)

dir_ls("data")

server <- ssh(host = "server.example.org", user = "user")
dir_ls("/data", con = server)
file_download("/data/input.csv", local = "input.csv", con = server)
```

`ssh_keygen()` generates an identity file for a server and prints the
`ssh-copy-id` command to register it there; it does not contact the server
itself:

```r
key <- ssh_keygen("server.example.org", user = "user")
#> Generated identity file: ~/.ssh/id_ed25519_user_server.example.org
#> Register it on the server by running:
#>   ssh-copy-id -i ~/.ssh/id_ed25519_user_server.example.org.pub user@server.example.org
server <- ssh(host = "server.example.org", user = "user", identity_file = key)
```

A destination ending in `/` represents a directory. Existing local and remote
directories are also detected when the trailing slash is omitted. netfs
appends the source basename in both transfer directions:

```r
file_upload("BAD26011.pdf", "/BAD-netfs/", con = server)
file_download("/reports/result.csv", "downloads/", con = server)
```

Uploads protect an existing remote file unless replacement is explicit:

```r
file_upload("BAD26011.pdf", "/BAD-netfs/", con = server, overwrite = TRUE)
```

Downloads use a numbered filename when `overwrite = FALSE`: an existing
`result.csv` produces `result-1.csv`, followed by `result-2.csv` when needed.

Transfer between two remote connections with `file_transfer()`. The operation
uses a temporary local staging file, which is removed after success or failure;
it is not a direct server-to-server copy:

```r
ftp_server <- ftp("ftp.example.org", user = "analyst")
smb_server <- smb("fileserver", "DATA", user = "analyst")

file_transfer(
  "/incoming/report.csv",
  "/archive/",
  from = ftp_server,
  to = smb_server
)
```

Substitute `ftp()` or `smb()` without changing the filesystem workflow:

```r
server <- smb(host = "fileserver", share = "DATA")
dir_ls("/reports", con = server)
```

List the connection root with either explicit or shorthand syntax:

```r
dir_ls(con = server)
dir_ls(server)
```

Remote paths may be written with or without a leading slash. Both forms refer
to the same path inside the connection root:

```r
dir_ls("/DEMANDES_DONNEES", con = server)
dir_ls("DEMANDES_DONNEES", con = server)
```

Connection construction validates configuration but does not contact the
server. Printed connections never include passwords.

## Credentials

Store credentials in the operating system credential store instead of source
code or connection objects:

```r
server <- ftp("ftp.example.org", user = "analyst")
set_creds(server) # securely prompts for the password
```

The connection stores only its host and username. `get_creds()` returns a
hidden S3 object, and `delete_creds()` removes the stored value:

```r
credential <- get_creds(server)
credential               # <hidden>
```

To select a named keyring, add only its name to `.Renviron`:

```text
NETFS_KEYRING=netfs
```

Do not put a password in `.Renviron`. When `password=` is supplied to a
connection constructor for compatibility, netfs immediately stores it through
`keyring` and does not retain it in the returned connection object.

## Backend requirements

| Backend | Client engine | Notes |
|---|---|---|
| Local | `fs` | Always available when the package is installed |
| FTP / FTPS | libcurl | Included through the `curl` package |
| SSH / SFTP | OpenSSH | Requires `ssh` and `scp` executables |
| SMB (all platforms) | [`smbclientr`](https://github.com/oousmane/smbclientr) | An optional (`Suggests`) dependency; install it to use `smb()` |

`smb()` delegates entirely to the `smbclientr` package, which provides its
own `fs`-style interface to SMB shares: Samba `smbclient` on Linux and macOS
(install with Homebrew — `brew install samba`; the MacPorts `samba4` port is
known to crash on connect on some macOS versions), and native Windows
UNC/filesystem support on Windows. `netfs` translates `smbclientr`'s errors
into its own condition classes and otherwise stays out of SMB protocol
mechanics entirely. See `smbclientr`'s own documentation for backend details.

Inspect the current system and a connection without contacting a server:

```r
netfs_capabilities()
netfs_capabilities(server)
```

## API coverage

Beyond the core operations above, `netfs` mirrors most of `fs`'s remaining
API for remote connections: `dir_info()`, `dir_map()`, `dir_walk()`,
`dir_tree()`, `dir_copy()`, `file_size()`, `file_create()`, `is_file()`,
`is_dir()`, `is_link()`, `is_file_empty()`, `is_dir_empty()`, `file_access()`,
`file_chmod()`, `file_chown()`, `file_touch()`, `link_create()`,
`link_path()`, `link_copy()`, and `link_delete()`. `dir_ls()`/`dir_info()`
also take a `recurse` argument.

A few `fs` functions have no `con =` counterpart at all, because they don't
operate on a connection's filesystem in the first place:
`fs::path_*()` (`path_join()`, `path_abs()`, `path_ext()`, ...) are pure
string manipulation and already work on a remote path string unchanged;
`fs::file_temp()`/`fs::path_temp()` name a *local* temporary file; and
`fs::group_ids()`/`fs::user_ids()` look up accounts on the *local* system.
Call the `fs::` versions directly for these.

`file_show()` is provided but always fails for a remote connection: it
opens a path in a local viewer application, which makes no sense for a path
that isn't on this machine. Download the file first, then call
`fs::file_show()` on the local copy.

## Current limitations

- Remote operations depend on the capabilities of the selected backend.
- Server-side `file_copy()` is unavailable for FTP (no copy command in the
  base protocol); it fails with `netfs_unsupported` instead of downloading
  and re-uploading the file. SSH supports it via `cp` on the remote shell,
  and SMB via `smbclientr` (`smbclient`'s `scopy` or native Windows copy).
  `dir_copy()` works on every backend regardless - on FTP, each file falls
  back to a local-staging download+upload instead of failing.
- POSIX permissions, ownership, arbitrary timestamps, and symlinks
  (`file_chmod()`, `file_chown()`, `file_touch()` with an explicit
  timestamp, `file_access()`'s `"read"`/`"write"`/`"execute"` modes,
  `link_create()`, `link_path()`, `link_copy()`, `link_delete()`) are
  SSH-only - FTP and SMB have no consistent equivalent, and fail with
  `netfs_unsupported`. `file_touch()` with an explicit timestamp
  additionally needs a GNU `touch` on the remote (confirmed against Linux
  and Windows/Git Bash remotes); BSD/macOS SSH remotes aren't currently
  supported for arbitrary timestamps, since BSD `touch -t`'s local-time
  semantics couldn't be verified without a reachable BSD SSH target.
- `file_transfer()` supports cross-connection transfers through temporary
  local staging. It is not a direct server-to-server operation.
- Password authentication for command-line SSH is not injected into process
  arguments. Use an SSH agent, SSH configuration, or an identity file. On
  Unix, operations on the same SSH connection share one OpenSSH
  `ControlMaster` connection rather than reconnecting per call (confirmed
  live: roughly a 9-13x speedup for repeated operations); not available on
  Windows.
- Normal unit tests use mocked transports and do not require live servers.

Remote failures inherit from `netfs_error`, with subclasses for authentication,
missing paths, permissions, timeouts, unavailable backends, and unsupported
operations.
