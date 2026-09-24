# Changelog

## netfs 0.1.0

- Added the initial local, SSH, FTP/FTPS, and SMB filesystem API.
- Added structured errors, capability reporting, and secret-safe
  connections.
- SMB client installation is left to the operating system. Missing Unix
  clients now produce platform-specific setup guidance.
- macOS SMB operations now use the separately installed Samba
  `smbclient` utility, the same as Linux, instead of mounting the share
  natively through AppleScript. Install it with Homebrew
  (`brew install samba`); the MacPorts `samba4` port is known to crash
  on connect on some macOS versions.
- Fixed FTP
  [`dir_create()`](https://oousmane.github.io/netfs/reference/dir_create.md),
  [`dir_delete()`](https://oousmane.github.io/netfs/reference/dir_delete.md),
  [`file_delete()`](https://oousmane.github.io/netfs/reference/file_delete.md),
  and
  [`file_move()`](https://oousmane.github.io/netfs/reference/file_move.md)
  silently no-op’ing instead of sending their commands.
- Fixed SMB directory listings
  ([`dir_ls()`](https://oousmane.github.io/netfs/reference/dir_ls.md))
  not parsing `smbclient`’s actual output format, and not listing a
  subdirectory’s contents without an explicit wildcard.
- Fixed an issue where an authenticated SMB call could lose its `PATH`
  and fail to find `smbclient`.
- Fixed `.run_command()` occasionally reporting unrelated errors (such
  as input validation failures) as a generic process-execution failure.
- Fixed
  [`file_download()`](https://oousmane.github.io/netfs/reference/file_download.md)/[`file_upload()`](https://oousmane.github.io/netfs/reference/file_upload.md)
  not expanding a `~` in `local`.
- Raised `smbclient`’s default send-buffer size to avoid
  `NT_STATUS_IO_TIMEOUT` on slower connections during large transfers;
  override with `smb(..., send_buffer = <bytes>)`.
- [`dir_ls()`](https://oousmane.github.io/netfs/reference/dir_ls.md)
  gained a `type` argument to filter remote listings by entry type,
  matching [`fs::dir_ls()`](https://fs.r-lib.org/reference/dir_ls.html).
- Remote
  [`dir_ls()`](https://oousmane.github.io/netfs/reference/dir_ls.md),
  [`file_info()`](https://oousmane.github.io/netfs/reference/file_info.md),
  and the mutating file/dir operations now return `fs`-typed results
  (`fs_path`, `fs_bytes`, and a
  [`fs::file_info()`](https://fs.r-lib.org/reference/file_info.html)
  compatible `type` factor) instead of plain character/numeric values.
- Added the concise
  [`set_creds()`](https://oousmane.github.io/netfs/reference/set_creds.md),
  [`get_creds()`](https://oousmane.github.io/netfs/reference/set_creds.md),
  and
  [`delete_creds()`](https://oousmane.github.io/netfs/reference/set_creds.md)
  keyring API.
- SMB support is now provided by the `smbclientr` package (an optional,
  `Suggests`-only dependency - installed only if you use
  [`smb()`](https://oousmane.github.io/netfs/reference/smb.md)).
  `netfs`’s own SMB implementation is gone;
  [`smb()`](https://oousmane.github.io/netfs/reference/smb.md),
  [`set_creds()`](https://oousmane.github.io/netfs/reference/set_creds.md)/[`get_creds()`](https://oousmane.github.io/netfs/reference/set_creds.md)/
  [`delete_creds()`](https://oousmane.github.io/netfs/reference/set_creds.md),
  and every remote filesystem operation keep their exact same public
  behavior, now as a thin adapter that translates `smbclientr`’s own
  errors into `netfs`’s condition classes. One user-visible improvement
  from the rebase: server-side
  [`file_copy()`](https://oousmane.github.io/netfs/reference/file_copy.md)
  is now supported for SMB (via `smbclient`’s `scopy` or native Windows
  copy), where it previously errored with `netfs_unsupported`.
- Fixed
  [`file_exists()`](https://oousmane.github.io/netfs/reference/file_exists.md)/[`file_info()`](https://oousmane.github.io/netfs/reference/file_info.md)
  on FTP effectively downloading a file’s entire contents just to check
  it exists (confirmed on a real server: 18s for a 22MB file, versus 4s
  with the fix - for a very large file this could take minutes or
  effectively hang). Uses curl’s `nobody = TRUE` (an FTP SIZE/MDTM
  query) instead of a full fetch.
- [`file_info()`](https://oousmane.github.io/netfs/reference/file_info.md)
  now returns real `size` and `modification_time` for FTP files
  (previously always `NA`), read from the same lightweight request.
- Fixed
  [`file_info()`](https://oousmane.github.io/netfs/reference/file_info.md)
  over SSH breaking against macOS/BSD remotes: it used `stat -c`,
  GNU-coreutils-specific syntax; falls back to BSD’s `stat -f` syntax if
  that fails.
- On Unix, operations on the same SSH connection now share one OpenSSH
  `ControlMaster` connection instead of opening a new one (full
  handshake and authentication) per call - confirmed live: roughly a
  9-13x speedup for repeated operations. Not available on Windows.
- Added
  [`ssh_keygen()`](https://oousmane.github.io/netfs/reference/ssh_keygen.md),
  a utility to generate an ed25519 identity file for an SSH connection
  and print the `ssh-copy-id` command that registers it on the server.
  It never contacts the server itself.
- Fixed
  [`file_upload()`](https://oousmane.github.io/netfs/reference/file_upload.md)/[`file_download()`](https://oousmane.github.io/netfs/reference/file_download.md)
  against remotes where a modern OpenSSH client’s default SFTP transfer
  is served by a process that doesn’t share the login shell’s view of
  the filesystem (confirmed live against Windows OpenSSH with a Git Bash
  default shell: `test -d`/`find` saw a path that the native
  `sftp-server` reported as missing). `scp` is now forced onto the
  legacy, shell-routed protocol (`-O`) for consistency with every other
  SSH operation.
- Fixed
  [`file_upload()`](https://oousmane.github.io/netfs/reference/file_upload.md)/[`file_download()`](https://oousmane.github.io/netfs/reference/file_download.md)
  mangling remote paths containing spaces or other shell-metacharacters,
  and fixed downloads of such a path failing outright with
  `protocol error: filename does not match request`. `scp`’s remote
  target is never parsed by a shell locally, and does no escaping of its
  own - it must arrive backslash-escaped for the remote shell, not
  `netfs`’s ordinary single-quote-style shell quoting (which, for
  downloads, broke `scp`’s own check that the server’s reported filename
  matches what was requested).
- Fixed
  [`file_info()`](https://oousmane.github.io/netfs/reference/file_info.md)
  over SSH failing with “SSH returned unrecognized metadata” against a
  Windows/MSYS2-packaged GNU coreutils `stat` (confirmed live over Git
  Bash): it printed the format string’s `\t` escape sequence verbatim
  instead of converting it to a tab the way Linux’s `stat` does, so
  netfs’s parser never found a field separator. The format string now
  embeds a literal tab byte instead, which every `stat` tested passes
  through unchanged without needing to interpret it.
- Added the rest of `fs`’s API for remote connections, backed entirely
  by the existing
  [`dir_ls()`](https://oousmane.github.io/netfs/reference/dir_ls.md)/[`file_info()`](https://oousmane.github.io/netfs/reference/file_info.md)/[`file_exists()`](https://oousmane.github.io/netfs/reference/file_exists.md)/[`dir_exists()`](https://oousmane.github.io/netfs/reference/dir_exists.md)/
  [`file_copy()`](https://oousmane.github.io/netfs/reference/file_copy.md)
  primitives so it works on every backend those already support:
  [`dir_info()`](https://oousmane.github.io/netfs/reference/dir_info.md),
  [`dir_map()`](https://oousmane.github.io/netfs/reference/dir_map.md),
  [`dir_walk()`](https://oousmane.github.io/netfs/reference/dir_walk.md),
  [`dir_tree()`](https://oousmane.github.io/netfs/reference/dir_tree.md),
  [`dir_copy()`](https://oousmane.github.io/netfs/reference/dir_copy.md),
  [`file_size()`](https://oousmane.github.io/netfs/reference/dir_ls.md),
  [`file_create()`](https://oousmane.github.io/netfs/reference/file_create.md),
  [`is_file()`](https://oousmane.github.io/netfs/reference/is_file.md),
  [`is_dir()`](https://oousmane.github.io/netfs/reference/is_file.md),
  [`is_link()`](https://oousmane.github.io/netfs/reference/is_file.md),
  [`is_file_empty()`](https://oousmane.github.io/netfs/reference/is_file.md),
  [`is_dir_empty()`](https://oousmane.github.io/netfs/reference/is_dir_empty.md).
  [`dir_ls()`](https://oousmane.github.io/netfs/reference/dir_ls.md)/[`dir_info()`](https://oousmane.github.io/netfs/reference/dir_info.md)
  also gained a `recurse` argument.
- Added
  [`file_chmod()`](https://oousmane.github.io/netfs/reference/file_chmod.md),
  [`file_chown()`](https://oousmane.github.io/netfs/reference/file_chown.md),
  [`file_touch()`](https://oousmane.github.io/netfs/reference/file_touch.md),
  [`file_access()`](https://oousmane.github.io/netfs/reference/file_access.md)
  (`"read"`/`"write"`/`"execute"` modes),
  [`link_create()`](https://oousmane.github.io/netfs/reference/link_create.md),
  [`link_path()`](https://oousmane.github.io/netfs/reference/link_path.md),
  [`link_copy()`](https://oousmane.github.io/netfs/reference/link_copy.md),
  and
  [`link_delete()`](https://oousmane.github.io/netfs/reference/link_delete.md).
  POSIX permissions, ownership, arbitrary timestamps, and symlinks have
  no consistent equivalent across FTP or SMB, so these are SSH-only
  (routed through the remote shell via
  `chmod`/`chown`/`touch`/`test -r|-w|-x`/`ln -s`/`readlink`); calling
  one on an FTP or SMB connection fails immediately with a clear
  `netfs_unsupported` error naming the operation and backend, rather
  than silently no-op’ing or leaking a generic error.
  [`file_touch()`](https://oousmane.github.io/netfs/reference/file_touch.md)
  with an explicit (non-“now”) timestamp additionally requires a GNU
  `touch` on the remote - BSD/macOS’s `-t` flag uses the server’s local
  time, which this project has had no reachable BSD SSH target to verify
  a correct conversion against.
- Added
  [`file_show()`](https://oousmane.github.io/netfs/reference/file_show.md),
  which is refused for any remote connection - it opens a path in a
  local viewer, and a remote path isn’t on this machine.
- Fixed
  [`file_info()`](https://oousmane.github.io/netfs/reference/file_info.md)
  over SSH never recognizing a symlink: GNU/BSD `stat` both describe one
  as some form of “symbolic link”, which matched neither the “directory”
  nor “file” branch, so its type silently came back `NA`.
- Fixed a missing remote path over SSH
  (e.g. [`file_info()`](https://oousmane.github.io/netfs/reference/file_info.md)
  on one) raising a generic `netfs_backend_error` instead of
  `netfs_not_found`, unlike every other backend - every coreutils tool
  tested reports a missing target with the same “No such file or
  directory” phrase.
- [`file_copy()`](https://oousmane.github.io/netfs/reference/file_copy.md)
  is now supported over SSH, using `cp` on the remote shell
  - the same connection every other SSH operation already runs through.
    It had been marked unsupported outright, the same as FTP (which
    genuinely has no copy command in the base protocol at all); SSH
    never needed the local download/upload round-trip that would imply,
    since a same-server copy never has to leave the server.
- [`dir_copy()`](https://oousmane.github.io/netfs/reference/dir_copy.md)
  no longer fails partway through (leaving an incomplete destination
  directory behind) on a backend without a native
  [`file_copy()`](https://oousmane.github.io/netfs/reference/file_copy.md) -
  currently just FTP. Each such file instead falls back to a
  local-staging download+upload, so the copy still completes.
- `netfs_capabilities(con)` now reports support for every operation
  above.
- Added a fourth remote backend,
  [`webdav()`](https://oousmane.github.io/netfs/reference/webdav.md),
  delegating to the `webdav` package (built on `httr2` alone - no
  external binary, unlike the SSH and SMB backends). A WebDAV connection
  is identified by a single base URL rather than host/port, since that
  URL commonly carries a server-specific path prefix (a per-user DAV
  root, for instance). Supports the full `netfs` API except the SSH-only
  permission/ownership/timestamp/symlink operations;
  [`file_move()`](https://oousmane.github.io/netfs/reference/file_move.md)
  is a copy followed by deleting the source (no native rename is
  exposed) - not atomic, so a failed delete leaves both copies behind
  rather than neither. Two real defects in the underlying `webdav`
  package were found and worked around, both confirmed live against a
  local WebDAV server: its error handling is inconsistent between
  functions (some throw on failure, others only warn and return
  `FALSE`/`NULL`, both now handled uniformly), and its directory listing
  always discards its first result row on the assumption it’s the
  queried collection’s own entry - true for a directory, but it silently
  drops a plain file’s only entry too, making a file and an empty
  directory indistinguishable by listing either directly; a specific
  path’s own type is instead always resolved by listing its parent.
- Fixed
  [`dir_ls()`](https://oousmane.github.io/netfs/reference/dir_ls.md)/[`dir_info()`](https://oousmane.github.io/netfs/reference/dir_info.md)
  over WebDAV producing garbage paths (the scheme and host embedded as
  bogus leading path segments) against some servers. RFC 4918 permits a
  PROPFIND response’s `<href>` to be either a server-relative path or a
  full absolute URL, server’s choice; confirmed live that a local
  WsgiDAV server uses the former and IT Hit’s .NET WebDAV Server
  (`webdavserver.net`) uses the latter. Both are now handled.
- Also fixed
  [`webdav()`](https://oousmane.github.io/netfs/reference/webdav.md)
  never actually checking that the `webdav` package was installed (the
  check function existed but nothing called it -
  [`smb()`](https://oousmane.github.io/netfs/reference/smb.md) already
  called its own equivalent check,
  [`webdav()`](https://oousmane.github.io/netfs/reference/webdav.md)
  didn’t), and applied the same construction-time check to the new
  [`s3()`](https://oousmane.github.io/netfs/reference/s3.md) connection
  below.
- Added a fifth remote backend,
  [`s3()`](https://oousmane.github.io/netfs/reference/s3.md), delegating
  to the `s3fs` package (built on `paws` alone - no external binary). A
  connection is scoped to one bucket, the same way
  [`smb()`](https://oousmane.github.io/netfs/reference/smb.md) is scoped
  to one share. Every `s3fs::s3_*()` convenience function shares one
  connection process-wide (a global cache `s3_file_system()` maintains
  internally), which would make a second
  [`s3()`](https://oousmane.github.io/netfs/reference/s3.md) connection
  silently clobber a first one still in use; `netfs` instead builds its
  own
  [`s3fs::S3FileSystem`](https://rdrr.io/pkg/s3fs/man/S3FileSystem.html)
  R6 object fresh per call and uses its methods directly, the same
  “rebuild, don’t share” approach already used for FTP’s curl handles.
- Two real defects in `s3fs` were found and worked around, both
  confirmed live against a local MinIO server:
  [`file_copy()`](https://oousmane.github.io/netfs/reference/file_copy.md)/[`file_move()`](https://oousmane.github.io/netfs/reference/file_move.md)
  internally decide between an S3-to-S3 copy, a download, or an upload
  by checking for a literal `"s3://"` prefix on the path - a bare
  `"bucket/key"` string (the format every other `s3fs` method here
  accepts and works with) matches none of the three, and the call
  reports success while silently doing nothing at all. And in
  [`file_info()`](https://oousmane.github.io/netfs/reference/file_info.md)
  specifically (which uses `future_lapply()` internally), a translated
  error thrown from inside a
  [`tryCatch()`](https://rdrr.io/r/base/conditions.html) handler was
  being re-caught by that same
  [`tryCatch()`](https://rdrr.io/r/base/conditions.html)’s own generic
  handler instead of reaching the caller - collapsing a precise
  `netfs_not_found`/`netfs_auth_error` down to a generic failure; fixed
  by resolving the outcome inside
  [`tryCatch()`](https://rdrr.io/r/base/conditions.html) and only
  throwing after it returns.
- [`dir_delete()`](https://oousmane.github.io/netfs/reference/dir_delete.md)
  without `recurse = TRUE` refuses a non-empty S3 “directory” the same
  way every other backend’s plain delete does, even though S3 itself has
  no atomic primitive for that - `s3fs`’s own
  [`dir_delete()`](https://oousmane.github.io/netfs/reference/dir_delete.md)
  is unconditionally recursive, so this checks with a listing first.
- AWS S3 authentication failures classify as `netfs_permission_error`
  (HTTP 403), not `netfs_auth_error` (401) - confirmed live that a wrong
  secret key comes back as 403 even from a S3-compatible server (MinIO),
  matching AWS’s own API convention of using 403 for both
  `SignatureDoesNotMatch` and genuine permission denials alike.
