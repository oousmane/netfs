#' Create an SMB connection description
#'
#' On Windows, operations use an existing authenticated Windows SMB session.
#' On macOS, operations mount the share with the native SMB client through
#' AppleScript and then use the mounted filesystem. Linux operations use the
#' separately installed Samba `smbclient` utility.
#' @param host SMB server hostname.
#' @param share Share name, separate from operation paths.
#' @param user Optional login name.
#' @param password Optional password. When supplied, it is written to the
#'   selected `keyring` credential store and is not retained in the connection.
#' @param domain Optional Windows domain.
#' @param ... Backend options.
#' @return A `netfs_smb` connection.
#' @family connection constructors
#' @examples
#' smb("fileserver", "DATA")
#' @export
smb <- function(host, share, user = NULL, password = NULL, domain = NULL, ...) {
  .check_scalar_character(host, "host")
  .check_scalar_character(share, "share")
  .check_optional_scalar_character(user, "user")
  .check_optional_scalar_character(password, "password")
  .check_optional_scalar_character(domain, "domain")
  share <- gsub("^[\\\\/]+|[\\\\/]+$", "", share)
  if (!nzchar(share) || grepl("[\\\\/]", share)) rlang::abort("`share` must be one SMB share name.", class = "netfs_validation_error")
  con <- new_netfs_connection("smb", list(host = trimws(host), share = share,
    user = user, domain = domain, options = list(...)))
  if (!is.null(password)) set_creds(con, password)
  con
}
