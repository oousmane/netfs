.run_command <- function(command, args = character(), timeout = NULL, env = NULL,
                         redact = character(), error_on_status = FALSE, ...) {
  .check_scalar_character(command, "command")
  if (!is.null(timeout) && (!is.numeric(timeout) || length(timeout) != 1L || timeout <= 0)) {
    rlang::abort("`timeout` must be a positive number of seconds.", class = "netfs_validation_error")
  }
  if (!nzchar(Sys.which(command))) abort_netfs_backend_unavailable(sprintf("Required executable `%s` is unavailable.", command), command = command)
  # Force all lazily-evaluated arguments here, outside the tryCatch below, so
  # an error while constructing them (e.g. path validation deep inside a
  # caller's `args` expression) surfaces with its own class and message
  # instead of being caught and rewritten as a process-execution failure.
  force(args); force(env); force(redact); force(error_on_status); list(...)
  result <- tryCatch(
    processx::run(command, args = args, error_on_status = FALSE,
      timeout = if (is.null(timeout)) Inf else timeout, env = env, ...),
    error = function(e) {
      if (grepl("timed out|timeout", conditionMessage(e), ignore.case = TRUE)) {
        abort_netfs_timeout(sprintf("Command `%s` timed out.", command), command = command)
      }
      abort_netfs_connection(sprintf("Command `%s` could not be executed.", command), command = command)
    }
  )
  if (isTRUE(result$timeout)) {
    abort_netfs_timeout(sprintf("Command `%s` timed out.", command), command = command)
  }
  out <- list(status = unname(result$status),
    stdout = .redact_text(result$stdout %||% "", redact),
    stderr = .redact_text(result$stderr %||% "", redact))
  if (error_on_status && out$status != 0L) abort_netfs_connection(sprintf("Command `%s` failed with status %d.", command, out$status), result = out)
  out
}

`%||%` <- function(x, y) if (is.null(x)) y else x
