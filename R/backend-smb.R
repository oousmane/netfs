# Thin adapter over smbclientr: netfs owns the generic filesystem
# abstraction and its own condition classes; smbclientr owns SMB protocol
# mechanics (smbclient invocation on Linux/macOS, native UNC on Windows,
# listing/metadata parsing, path conversion, credential storage). Backend
# errors from smbclientr are translated into netfs's own condition classes
# so netfs's error-class contract does not change for its users.
.smb_translate <- function(expr) {
  tryCatch(expr,
    smbclientr_auth_error = function(e) abort_netfs_auth(conditionMessage(e), parent = e),
    smbclientr_not_found = function(e) abort_netfs_not_found(conditionMessage(e), parent = e),
    smbclientr_permission_error = function(e) abort_netfs_permission(conditionMessage(e), parent = e),
    smbclientr_timeout = function(e) abort_netfs_timeout(conditionMessage(e), parent = e),
    smbclientr_backend_unavailable = function(e) abort_netfs_backend_unavailable(conditionMessage(e), parent = e),
    smbclientr_unsupported = function(e) abort_netfs_unsupported(conditionMessage(e), parent = e),
    smbclientr_destination_exists = function(e) abort_netfs(conditionMessage(e), "netfs_destination_exists", parent = e),
    smbclientr_error = function(e) abort_netfs_connection(conditionMessage(e), parent = e)
  )
}

.dir_ls.netfs_smb <- function(con, path, type = "any", ...) {
  .smb_translate(as.character(smbclientr::dir_ls(path, con = con, type = type, ...)))
}

.dir_info.netfs_smb <- function(con, path, type = "any", ...) {
  .smb_translate(smbclientr::dir_info(path, con = con, type = type, ...))
}

.dir_exists.netfs_smb <- function(con, path, ...) {
  .smb_translate(unname(smbclientr::dir_exists(path, con = con)))
}

.dir_create.netfs_smb <- function(con, path, ...) {
  .smb_translate(invisible(as.character(smbclientr::dir_create(path, con = con, ...))))
}

.dir_delete.netfs_smb <- function(con, path, ...) {
  .smb_translate(invisible(as.character(smbclientr::dir_delete(path, con = con))))
}

.file_exists.netfs_smb <- function(con, path, ...) {
  .smb_translate(unname(smbclientr::file_exists(path, con = con)))
}

.file_delete.netfs_smb <- function(con, path, ...) {
  .smb_translate(invisible(as.character(smbclientr::file_delete(path, con = con))))
}

.file_copy.netfs_smb <- function(con, path, new_path, ...) {
  .smb_translate(invisible(as.character(smbclientr::file_copy(path, new_path, con = con, ...))))
}

.file_move.netfs_smb <- function(con, path, new_path, ...) {
  .smb_translate(invisible(as.character(smbclientr::file_move(path, new_path, con = con))))
}

.file_info.netfs_smb <- function(con, path, ...) {
  .smb_translate(smbclientr::file_info(path, con = con, ...))
}

.file_download.netfs_smb <- function(con, path, local, ...) {
  .smb_translate(invisible(as.character(smbclientr::file_download(path, local, con = con))))
}

.file_upload.netfs_smb <- function(con, local, path, ...) {
  .smb_translate(invisible(as.character(smbclientr::file_upload(local, path, con = con))))
}
