#' Create an SSH connection description
#'
#' Authentication may use SSH configuration, an agent, or an identity file.
#' OpenSSH is run with `BatchMode=yes`, so it can never prompt for or accept
#' a password - a stored `password` (see `password` below) is not usable
#' for authentication as a result; it is kept only for callers that manage
#' authentication another way. Construction does not contact the server.
#'
#' On Unix, operations on the same connection share one OpenSSH
#' `ControlMaster` connection instead of opening a new one (full handshake
#' and authentication) per call - the first operation establishes it, later
#' ones reuse it automatically. Not available on Windows (unreliable
#' `ControlMaster` support in Windows OpenSSH), where each call still opens
#' its own connection as before.
#' @param host Server hostname.
#' @param user Optional login name.
#' @param port SSH port.
#' @param password Optional password to store in `keyring`. OpenSSH
#'   command-line operations do not place this value on the command line;
#'   prefer an SSH agent, SSH configuration, or `identity_file`.
#' @param identity_file Optional private-key path.
#' @param ... Backend options.
#' @return A `netfs_ssh` connection.
#' @family connection constructors
#' @examples
#' ssh("server.example.org", user = "user")
#' @export
ssh <- function(host, user = NULL, port = 22, password = NULL, identity_file = NULL, ...) {
  .check_scalar_character(host, "host")
  .check_optional_scalar_character(user, "user")
  .check_optional_scalar_character(password, "password")
  .check_optional_scalar_character(identity_file, "identity_file")
  con <- new_netfs_connection("ssh", list(host = trimws(host), user = user,
    port = .check_port(port), identity_file = identity_file, options = list(...)))
  if (!is.null(password)) set_creds(con, password)
  con
}
