#' Create an FTP or FTPS connection description
#'
#' Construction validates settings but does not contact the server.
#' @param host Server hostname, with or without an FTP scheme.
#' @param user Optional login name.
#' @param password Optional password. When supplied, it is written to the
#'   selected `keyring` credential store and is not retained in the connection.
#' @param port Server port.
#' @param tls Use explicit TLS through libcurl.
#' @param ... Backend options retained for future requests.
#' @return A `netfs_ftp` connection.
#' @family connection constructors
#' @examples
#' ftp("ftp.example.org")
#' @export
ftp <- function(host, user = NULL, password = NULL, port = 21, tls = FALSE, ...) {
  .check_scalar_character(host, "host")
  .check_optional_scalar_character(user, "user")
  .check_optional_scalar_character(password, "password")
  .check_scalar_logical(tls, "tls")
  host <- sub("^ftps?://", "", trimws(host), ignore.case = TRUE)
  host <- sub("/+$", "", host)
  if (!nzchar(host) || grepl("/", host, fixed = TRUE)) rlang::abort("`host` must contain only an FTP server name.", class = "netfs_validation_error")
  con <- new_netfs_connection("ftp", list(host = host, user = user,
    port = .check_port(port), tls = tls, options = list(...)))
  if (!is.null(password)) set_creds(con, password)
  con
}
