.netfs_keyring <- function(keyring = NULL) {
  if (!is.null(keyring)) {
    .check_scalar_character(keyring, "keyring")
    return(keyring)
  }
  configured <- Sys.getenv("NETFS_KEYRING", unset = "")
  if (nzchar(configured)) configured else NULL
}

.credential_service <- function(con) {
  .check_connection(con)
  backend <- sub("^netfs_", "", class(con)[[1L]])
  endpoint <- switch(class(con)[[1L]],
    netfs_ftp = paste0(con$host, ":", con$port),
    netfs_ssh = paste0(con$host, ":", con$port),
    netfs_smb = paste0(con$host, "/", con$share),
    netfs_webdav = con$url,
    netfs_s3 = con$bucket
  )
  paste("netfs", backend, endpoint, sep = ":")
}

.credential_username <- function(con) con$user %||% NULL

.keyring_set <- function(service, username, keyring) {
  keyring::key_set(service = service, username = username, keyring = keyring)
}

.keyring_set_with_value <- function(service, username, password, keyring) {
  keyring::key_set_with_value(
    service = service,
    username = username,
    password = password,
    keyring = keyring
  )
}

.keyring_get <- function(service, username, keyring) {
  keyring::key_get(service = service, username = username, keyring = keyring)
}

.keyring_delete <- function(service, username, keyring) {
  keyring::key_delete(service = service, username = username, keyring = keyring)
}

new_netfs_creds <- function(value) {
  .check_scalar_character(value, "credential")
  structure(list(value = value), class = "netfs_creds")
}

#' Hidden credential display
#' @param x,object A credential object returned by [get_creds()].
#' @param ... Unused.
#' @return `print()` returns `x` invisibly, `format()` returns the hidden
#'   marker, and `str()` returns `NULL` invisibly.
#' @keywords internal
#' @export
print.netfs_creds <- function(x, ...) {
  cat("<netfs_creds>\n<hidden>\n")
  invisible(x)
}

#' @rdname print.netfs_creds
#' @export
format.netfs_creds <- function(x, ...) "<hidden>"

#' @rdname print.netfs_creds
#' @export
str.netfs_creds <- function(object, ...) {
  cat("netfs_creds <hidden>\n")
  invisible(NULL)
}

#' Manage credentials for a remote connection
#'
#' Credentials are stored in the operating system credential store through
#' `keyring`. The connection object contains no password. Set `NETFS_KEYRING`
#' in `.Renviron` to select a named keyring; leave it unset to use the system
#' default keyring. Never place the password itself in `.Renviron`.
#'
#' @param con A connection created by [ftp()], [ssh()], or [smb()].
#' @param password Optional password. When `NULL`,
#'   [keyring::key_set()] requests it interactively without echoing it.
#' @param keyring Optional keyring name. By default, uses `NETFS_KEYRING` and
#'   then the system default keyring.
#' @return `set_creds()` and `delete_creds()` return `con` invisibly.
#'   `get_creds()` returns a hidden `netfs_creds` object.
#' @family connection constructors
#' @examples
#' \dontrun{
#' con <- ftp("ftp.example.org", user = "analyst")
#' set_creds(con)
#' get_creds(con)
#' delete_creds(con)
#' }
#' @export
set_creds <- function(con, password = NULL, keyring = NULL) {
  .check_connection(con)
  # SMB credential storage is owned by smbclientr, not netfs - it knows
  # nothing about how smbclient/Windows native SMB actually consumes them.
  if (inherits(con, "netfs_smb")) return(smbclientr::set_creds(con, password = password, keyring = keyring))
  keyring <- .netfs_keyring(keyring)
  service <- .credential_service(con)
  username <- .credential_username(con)
  if (is.null(password)) {
    .keyring_set(service, username, keyring)
  } else {
    .check_scalar_character(password, "password")
    .keyring_set_with_value(service, username, password, keyring)
  }
  invisible(con)
}

#' @rdname set_creds
#' @export
get_creds <- function(con, keyring = NULL) {
  .check_connection(con)
  if (inherits(con, "netfs_smb")) return(new_netfs_creds(smbclientr::get_creds(con, keyring = keyring)))
  new_netfs_creds(
    .keyring_get(
      .credential_service(con),
      .credential_username(con),
      .netfs_keyring(keyring)
    )
  )
}

#' @rdname set_creds
#' @export
delete_creds <- function(con, keyring = NULL) {
  .check_connection(con)
  if (inherits(con, "netfs_smb")) { smbclientr::delete_creds(con, keyring = keyring); return(invisible(con)) }
  .keyring_delete(
    .credential_service(con),
    .credential_username(con),
    .netfs_keyring(keyring)
  )
  invisible(con)
}

.connection_password <- function(con, required = FALSE) {
  if (inherits(con, "netfs_smb")) return(smbclientr:::.connection_password(con, required = required))
  tryCatch(
    .keyring_get(
      .credential_service(con),
      .credential_username(con),
      .netfs_keyring()
    ),
    error = function(e) {
      if (required) {
        abort_netfs_auth(
          sprintf("No credential is available for `%s`.", con$host),
          parent = e
        )
      }
      NULL
    }
  )
}
