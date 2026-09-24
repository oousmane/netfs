.require_webdav <- function() {
  if (requireNamespace("webdav", quietly = TRUE)) return(invisible(TRUE))
  abort_netfs_backend_unavailable(
    "WebDAV connections require the webdav package. Install it first.",
    command = "webdav"
  )
}

#' Create a WebDAV connection description
#'
#' WebDAV is identified by a single base URL rather than a separate host and
#' share/port, since that URL commonly includes a server-specific path
#' prefix (for example a per-user DAV root on a file-sync server). Support
#' is provided by the webdav package. Construction doesn't contact the
#' server.
#' @param url The server's base WebDAV URL, e.g.
#'   `"https://cloud.example.org/remote.php/dav/files/alice/"`.
#' @param user Optional login name.
#' @param password Optional password. When supplied, it is written to the
#'   selected `keyring` credential store and is not retained in the connection.
#' @param ... Backend options.
#' @return A `netfs_webdav` connection.
#' @family connection constructors
#' @examples
#' \dontrun{
#' webdav("https://cloud.example.org/remote.php/dav/files/alice/", user = "alice")
#' }
#' @export
webdav <- function(url, user = NULL, password = NULL, ...) {
  .require_webdav()
  .check_scalar_character(url, "url")
  .check_optional_scalar_character(user, "user")
  .check_optional_scalar_character(password, "password")
  if (!grepl("^https?://", url, ignore.case = TRUE)) {
    rlang::abort("`url` must be an http(s) URL.", class = "netfs_validation_error")
  }
  url <- paste0(sub("/+$", "", url), "/")
  con <- new_netfs_connection("webdav", list(host = url, url = url, user = user, options = list(...)))
  if (!is.null(password)) set_creds(con, password)
  con
}
