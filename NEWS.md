# netfs 0.1.0

* Added the initial local, SSH, FTP/FTPS, and SMB filesystem API.
* Added structured errors, capability reporting, and secret-safe connections.
* SMB client installation is left to the operating system. Missing Unix
  clients now produce platform-specific setup guidance.
* macOS SMB operations now use the separately installed Samba `smbclient`
  utility, the same as Linux, instead of mounting the share natively through
  AppleScript. Install it with Homebrew (`brew install samba`); the MacPorts
  `samba4` port is known to crash on connect on some macOS versions.
* Fixed FTP `dir_create()`, `dir_delete()`, `file_delete()`, and `file_move()`
  silently no-op'ing instead of sending their commands.
* Fixed SMB directory listings (`dir_ls()`) not parsing `smbclient`'s actual
  output format, and not listing a subdirectory's contents without an
  explicit wildcard.
* Fixed an issue where an authenticated SMB call could lose its `PATH` and
  fail to find `smbclient`.
* Fixed `.run_command()` occasionally reporting unrelated errors (such as
  input validation failures) as a generic process-execution failure.
* Fixed `file_download()`/`file_upload()` not expanding a `~` in `local`.
* Raised `smbclient`'s default send-buffer size to avoid `NT_STATUS_IO_TIMEOUT`
  on slower connections during large transfers; override with
  `smb(..., send_buffer = <bytes>)`.
* `dir_ls()` gained a `type` argument to filter remote listings by entry
  type, matching `fs::dir_ls()`.
* Remote `dir_ls()`, `file_info()`, and the mutating file/dir operations now
  return `fs`-typed results (`fs_path`, `fs_bytes`, and a `fs::file_info()`
  compatible `type` factor) instead of plain character/numeric values.
* Added the concise `set_creds()`, `get_creds()`, and `delete_creds()` keyring
  API.
* SMB support is now provided by the `smbclientr` package (an optional,
  `Suggests`-only dependency - installed only if you use `smb()`). `netfs`'s
  own SMB implementation is gone; `smb()`, `set_creds()`/`get_creds()`/
  `delete_creds()`, and every remote filesystem operation keep their exact
  same public behavior, now as a thin adapter that translates `smbclientr`'s
  own errors into `netfs`'s condition classes. One user-visible improvement
  from the rebase: server-side `file_copy()` is now supported for SMB (via
  `smbclient`'s `scopy` or native Windows copy), where it previously errored
  with `netfs_unsupported`.
