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
| SMB on Linux/macOS | `smbclient` | Must be installed separately |
| SMB on Windows | Windows UNC | Uses the current authenticated Windows session |

On Linux or macOS, inspect the installation command before installing the SMB
client:

```r
install_smbclient(dry_run = TRUE)
install_smbclient() # asks before changing the system
```

Installation commands run through `processx` with a per-command timeout.
On systems that require `sudo`, authenticate first with `sudo -v`; the
installer never waits on a hidden password prompt.

Inspect the current system and a connection without contacting a server:

```r
netfs_capabilities()
netfs_capabilities(server)
```

## Current limitations

- Remote operations depend on the capabilities of the selected backend.
- Server-side `file_copy()` is unavailable for SSH, FTP, and Unix
  `smbclient`; it fails with `netfs_unsupported` instead of downloading and
  re-uploading the file.
- `file_transfer()` supports cross-connection transfers through temporary
  local staging. It is not a direct server-to-server operation.
- Password authentication for command-line SSH is not injected into process
  arguments. Use an SSH agent, SSH configuration, or an identity file.
- Normal unit tests use mocked transports and do not require live servers.

## Integration testing

The `Backend integration` GitHub Actions workflow provisions disposable
OpenSSH, vsftpd, and Samba services on an Ubuntu runner. It exercises live SSH,
FTP, and SMB operations plus an FTP-to-SMB `file_transfer()`. The integration
tests remain skipped during ordinary local tests unless
`NETFS_RUN_INTEGRATION=true` is set.

Remote failures inherit from `netfs_error`, with subclasses for authentication,
missing paths, permissions, timeouts, unavailable backends, and unsupported
operations.
