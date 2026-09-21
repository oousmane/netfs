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
  operations <- c("dir_ls", "dir_exists", "dir_create", "dir_delete", "file_exists",
    "file_delete", "file_copy", "file_move", "file_info", "file_download", "file_upload")
  supported <- switch(class(con)[[1L]],
    netfs_ssh = operations != "file_copy",
    netfs_ftp = !operations %in% c("file_copy"),
    # scopy (smbclient) or native UNC copy: file_copy is supported either way.
    netfs_smb = rep(TRUE, length(operations))
  )
  tibble::tibble(operation = operations, supported = supported)
}
