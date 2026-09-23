.has_command <- function(x) nzchar(Sys.which(x))
.has_ssh <- function() .has_command("ssh")
.has_sftp <- function() .has_command("sftp")
.has_scp <- function() .has_command("scp")
.has_curl <- function() isTRUE(curl::curl_version()$version != "")

#' Report netfs backend capabilities
#'
#' This function reports static client availability or operations supported by
#' a connection class. It never contacts a remote server.
#' @param con Optional netfs connection.
#' @return A tibble describing backends or supported operations.
#' @examples
#' netfs_capabilities()
#' netfs_capabilities(ssh("server.example.org"))
#' @export
netfs_capabilities <- function(con = NULL) {
  if (is.null(con)) {
    smb <- if (requireNamespace("smbclientr", quietly = TRUE)) smbclientr::smb_capabilities() else NULL
    return(tibble::tibble(
      backend = c("local", "ftp", "ssh", "smb"),
      available = c(TRUE, .has_curl(), .has_ssh() && .has_scp(), isTRUE(smb$available)),
      engine = c("fs", "libcurl", "OpenSSH", if (is.null(smb)) NA_character_ else smb$engine)
    ))
  }
  .check_connection(con)
  operations <- c("dir_ls", "dir_info", "dir_exists", "dir_create", "dir_delete", "dir_copy",
    "file_exists", "file_delete", "file_copy", "file_move", "file_info", "file_download",
    "file_upload", "file_create", "file_chmod", "file_chown", "file_touch",
    "file_access (read/write/execute)", "link_create", "link_path", "link_copy", "link_delete")
  # file_copy has no equivalent in the base FTP protocol (no RFC959 "copy"
  # command), so it's unsupported there; SSH uses `cp` on the remote shell,
  # and SMB uses smbclientr's scopy/native UNC copy. dir_copy() works on
  # every backend regardless (including FTP): each file falls back to a
  # local-staging download+upload when the backend has no native copy.
  # Every POSIX-permission/ownership/timestamp/symlink operation is
  # SSH-only, since it's the only backend routed through a real remote
  # shell - FTP and SMB have no consistent equivalent.
  ssh_only <- c("file_chmod", "file_chown", "file_touch", "file_access (read/write/execute)",
    "link_create", "link_path", "link_copy", "link_delete")
  supported <- switch(class(con)[[1L]],
    netfs_ssh = rep(TRUE, length(operations)),
    netfs_ftp = !operations %in% c("file_copy", ssh_only),
    netfs_smb = !operations %in% ssh_only
  )
  tibble::tibble(operation = operations, supported = supported)
}
