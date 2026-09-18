.has_command <- function(x) nzchar(Sys.which(x))
.has_ssh <- function() .has_command("ssh")
.has_sftp <- function() .has_command("sftp")
.has_scp <- function() .has_command("scp")
.has_smbclient <- function() .has_command("smbclient")
.has_macos_smb <- function() .is_macos() && .has_command("osascript")
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
    smb_engine <- if (.is_windows()) {
      "Windows UNC"
    } else if (.is_macos()) {
      "macOS SMB"
    } else {
      "smbclient"
    }
    return(tibble::tibble(
      backend = c("local", "ftp", "ssh", "smb"),
      available = c(TRUE, .has_curl(), .has_ssh() && .has_scp(),
        .is_windows() || .has_macos_smb() || .has_smbclient()),
      engine = c("fs", "libcurl", "OpenSSH", smb_engine)
    ))
  }
  .check_connection(con)
  operations <- c("dir_ls", "dir_exists", "dir_create", "dir_delete", "file_exists",
    "file_delete", "file_copy", "file_move", "file_info", "file_download", "file_upload")
  supported <- switch(class(con)[[1L]],
    netfs_ssh = operations != "file_copy",
    netfs_ftp = !operations %in% c("file_copy"),
    netfs_smb = if (.smb_uses_native_fs()) rep(TRUE, length(operations)) else operations != "file_copy"
  )
  tibble::tibble(operation = operations, supported = supported)
}
