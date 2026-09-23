#' Generate an SSH identity file for a connection
#'
#' Creates a new ed25519 keypair under `~/.ssh` (reusing one already at the
#' target `path` unless `overwrite = TRUE`) and prints the `ssh-copy-id`
#' command that registers the public key on the server. netfs never contacts
#' the server itself here: registering a key needs your existing password or
#' access once, and SSH's own `BatchMode=yes` policy (see [ssh()]) means
#' netfs can never supply one interactively - `ssh-copy-id` is the standard
#' tool for that step.
#'
#' @param host,user,port As passed to [ssh()]; used to build a descriptive
#'   key filename and the suggested `ssh-copy-id` command.
#' @param path Optional private-key path. Defaults to
#'   `~/.ssh/id_ed25519_<user>_<host>` (or `~/.ssh/id_ed25519_<host>` when
#'   `user` is `NULL`), with characters unsafe for a filename replaced by
#'   `_`.
#' @param overwrite Regenerate an existing key at `path`? Default `FALSE`
#'   reuses it as-is.
#' @return The identity file path, invisibly. Pass it as
#'   `ssh(..., identity_file = )`.
#' @family connection constructors
#' @examples
#' \dontrun{
#' key <- ssh_keygen("server.example.org", user = "alice")
#' con <- ssh("server.example.org", user = "alice", identity_file = key)
#' }
#' @export
ssh_keygen <- function(host, user = NULL, port = 22, path = NULL, overwrite = FALSE) {
  .check_scalar_character(host, "host")
  .check_optional_scalar_character(user, "user")
  port <- .check_port(port)
  .check_optional_scalar_character(path, "path")
  .check_scalar_logical(overwrite, "overwrite")

  if (!nzchar(Sys.which("ssh-keygen"))) {
    abort_netfs_backend_unavailable("Required executable `ssh-keygen` is unavailable.", command = "ssh-keygen")
  }

  slug <- gsub("[^A-Za-z0-9._-]+", "_", paste(c(user, host), collapse = "_"))
  path <- fs::path_expand(path %||% fs::path_home(".ssh", paste0("id_ed25519_", slug)))
  pub_path <- paste0(path, ".pub")

  if (fs::file_exists(path) && !overwrite) {
    message("Using existing identity file: ", path)
  } else {
    if (fs::file_exists(path)) fs::file_delete(path)
    if (fs::file_exists(pub_path)) fs::file_delete(pub_path)
    fs::dir_create(fs::path_dir(path), mode = "700")
    result <- .run_command("ssh-keygen",
      c("-q", "-t", "ed25519", "-N", "", "-C", paste0("netfs-", slug), "-f", path))
    if (result$status != 0L) {
      abort_netfs(sprintf("ssh-keygen failed: %s", trimws(paste(result$stderr, result$stdout))),
        "netfs_backend_error", result = result)
    }
    message("Generated identity file: ", path)
  }

  target <- if (is.null(user)) host else paste0(user, "@", host)
  copy_cmd <- paste0("ssh-copy-id -i ", pub_path, if (port != 22L) paste0(" -p ", port) else "", " ", target)
  message("Register it on the server by running:\n  ", copy_cmd)
  invisible(path)
}
