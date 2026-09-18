# netfs 0.1.0

* Added the initial local, SSH, FTP/FTPS, and SMB filesystem API.
* Added structured errors, capability reporting, and secret-safe connections.
* SMB client installation is left to the operating system. Missing Unix
  clients now produce platform-specific setup guidance.
* macOS SMB operations use the native client directly from R; no Samba
  installation is required.
* Added the concise `set_creds()`, `get_creds()`, and `delete_creds()` keyring
  API.
