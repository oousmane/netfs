#' Create an SSH connection description
#'
#' Authenticate with an SSH agent, SSH configuration, or `identity_file`.
#' OpenSSH runs with `BatchMode=yes`, so it never prompts for a password;
#' `password` is stored for callers that authenticate another way, not for
#' netfs itself. Construction doesn't contact the server.
#'
#' On Unix, operations on one connection share a single OpenSSH
#' `ControlMaster` session instead of reconnecting on every call. Not
#' available on Windows, where OpenSSH's `ControlMaster` support is
#' unreliable; each call opens its own connection there instead.
#' @param host Server hostname.
#' @param user Optional login name.
#' @param port SSH port.
#' @param password Optional password to store in `keyring`, for callers
#'   that manage authentication themselves; prefer an SSH agent, SSH
#'   configuration, or `identity_file` for netfs's own use.
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
