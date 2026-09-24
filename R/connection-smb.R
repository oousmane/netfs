.require_smbclientr <- function() {
  if (requireNamespace("smbclientr", quietly = TRUE)) return(invisible(TRUE))
  abort_netfs_backend_unavailable(
    "SMB connections require the smbclientr package. Install it first.",
    command = "smbclientr"
  )
}

#' Create an SMB connection description
#'
#' SMB support is provided by the smbclientr package: native UNC access on
#' Windows, and Samba's `smbclient` (`brew install samba`) on macOS and
#' Linux. See `smbclientr::smb_connection()` for backend details.
#' @param host SMB server hostname.
#' @param share Share name, separate from operation paths.
#' @param user Optional login name.
#' @param password Optional password. When supplied, it is written to the
#'   selected `keyring` credential store and is not retained in the connection.
#' @param domain Optional Windows domain.
#' @param ... Additional arguments passed to `smbclientr::smb_connection()`
#'   (for example `send_buffer`).
#' @return A `netfs_smb` connection. This object is also a valid smbclientr
#'   `smb_connection` - the same fields (`host`, `share`, `user`, `domain`)
#'   are not duplicated between the two packages.
#' @family connection constructors
#' @examples
#' \dontrun{
#' smb("fileserver", "DATA")
#' }
#' @export
smb <- function(host, share, user = NULL, password = NULL, domain = NULL, ...) {
  .require_smbclientr()
  con <- smbclientr::smb_connection(host = host, share = share, user = user,
    password = password, domain = domain, ...)
  class(con) <- c("netfs_smb", "netfs_connection", class(con))
  con
}
