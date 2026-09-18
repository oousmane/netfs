.available_package_managers <- function() {
  managers <- c("apt-get", "dnf", "yum", "pacman", "apk", "zypper", "brew")
  locations <- Sys.which(managers)
  names(locations)[nzchar(locations)]
}

.smbclient_install_plan <- function(os = tolower(Sys.info()[["sysname"]]),
                                    commands = .available_package_managers()) {
  if (identical(os, "darwin")) {
    if (!"brew" %in% commands) {
      abort_netfs_backend_unavailable(
        "Homebrew is required to install `smbclient` automatically on macOS."
      )
    }
    return(list(list(command = "brew", args = c("install", "samba"))))
  }

  if (!identical(os, "linux")) {
    abort_netfs_unsupported(
      "Automatic `smbclient` installation is supported only on Linux and macOS."
    )
  }

  candidates <- list(
    `apt-get` = list(
      list(command = "apt-get", args = "update"),
      list(command = "apt-get", args = c("install", "-y", "smbclient"))
    ),
    dnf = list(list(command = "dnf", args = c("install", "-y", "samba-client"))),
    yum = list(list(command = "yum", args = c("install", "-y", "samba-client"))),
    pacman = list(list(command = "pacman", args = c("-S", "--noconfirm", "--needed", "smbclient"))),
    apk = list(list(command = "apk", args = c("add", "samba-client"))),
    zypper = list(list(command = "zypper", args = c("--non-interactive", "install", "samba-client")))
  )
  matching <- names(candidates)[names(candidates) %in% commands]
  if (!length(matching)) {
    abort_netfs_backend_unavailable(
      "No supported package manager was found. Install the Samba `smbclient` executable manually."
    )
  }
  manager <- matching[[1L]]
  candidates[[manager]]
}

.format_install_step <- function(step, elevated = FALSE) {
  command <- if (elevated) paste("sudo -n", step$command) else step$command
  paste(c(command, vapply(step$args, shQuote, character(1))), collapse = " ")
}

.processx_run <- function(...) processx::run(...)

.run_install_step <- function(step, elevated = FALSE, timeout = 600) {
  command <- step$command
  args <- step$args
  if (elevated) {
    command <- "sudo"
    args <- c("-n", step$command, step$args)
  }

  result <- tryCatch(
    .processx_run(
      command,
      args = args,
      error_on_status = FALSE,
      timeout = timeout,
      stdin = "",
      cleanup_tree = TRUE,
      windows_hide_window = TRUE
    ),
    error = function(e) {
      if (grepl("timed out|timeout", conditionMessage(e), ignore.case = TRUE)) {
        abort_netfs_timeout(
          sprintf("Installation command timed out after %s seconds.", timeout),
          command = command,
          parent = e
        )
      }
      abort_netfs_connection(
        sprintf("Installation command '%s' could not be executed.", command),
        command = command,
        parent = e
      )
    }
  )

  if (isTRUE(result$timeout)) {
    abort_netfs_timeout(
      sprintf("Installation command timed out after %s seconds.", timeout),
      command = command
    )
  }

  out <- list(
    status = unname(result$status),
    stdout = result$stdout %||% "",
    stderr = result$stderr %||% ""
  )
  if (out$status != 0L) {
    message <- if (elevated) {
      paste0(
        "The installer could not obtain non-interactive administrator access. ",
        "Run 'sudo -v' in a terminal, then retry."
      )
    } else {
      sprintf("Installation command '%s' failed with status %d.", command, out$status)
    }
    abort_netfs_connection(message, command = command, result = out)
  }
  out
}

#' Install the SMB command-line client
#'
#' Installs the operating-system package that supplies `smbclient` on Linux or
#' macOS. Windows uses native UNC paths and does not require this executable.
#' Installation changes the host system and may request administrator access,
#' so the command is displayed and confirmation is required by default.
#'
#' @param dry_run Display the selected installation commands without executing
#'   them.
#' @param ask Ask for confirmation before changing the system. In
#'   non-interactive sessions, explicitly set `ask = FALSE` to authorize the
#'   installation.
#' @param timeout Maximum number of seconds allowed for each installation
#'   command.
#' @return `TRUE`, invisibly, when `smbclient` is available or Windows native
#'   SMB support applies. A dry run returns the installation plan invisibly.
#' @examples
#' \dontrun{
#' install_smbclient(dry_run = TRUE)
#' install_smbclient()
#' }
#' @export
install_smbclient <- function(dry_run = FALSE, ask = TRUE, timeout = 600) {
  .check_scalar_logical(dry_run, "dry_run")
  .check_scalar_logical(ask, "ask")
  if (!is.numeric(timeout) || length(timeout) != 1L ||
      is.na(timeout) || !is.finite(timeout) || timeout <= 0) {
    rlang::abort(
      "`timeout` must be a positive number of seconds.",
      class = "netfs_validation_error"
    )
  }
  if (.Platform$OS.type == "windows") {
    message("Windows uses native UNC paths; `smbclient` is not required.")
    return(invisible(TRUE))
  }
  if (.has_smbclient()) {
    message("`smbclient` is already installed at ", Sys.which("smbclient"), ".")
    return(invisible(TRUE))
  }

  plan <- .smbclient_install_plan()
  elevated <- identical(tolower(Sys.info()[["sysname"]]), "linux") &&
    (!is.function(get0("Sys.getuid", mode = "function")) || Sys.getuid() != 0L)
  commands <- vapply(plan, .format_install_step, character(1), elevated = elevated)
  message("The following command", if (length(commands) == 1L) "" else "s", " will be used:\n",
    paste0("  ", commands, collapse = "\n"))
  if (dry_run) return(invisible(plan))

  if (ask) {
    if (!interactive()) {
      rlang::abort(
        "Installation requires confirmation; rerun with `ask = FALSE` to authorize it.",
        class = "netfs_install_confirmation_required"
      )
    }
    answer <- readline("Install smbclient now? [y/N] ")
    if (!tolower(trimws(answer)) %in% c("y", "yes")) {
      rlang::abort("`smbclient` installation was cancelled.", class = "netfs_install_cancelled")
    }
  }

  for (step in plan) {
    .run_install_step(step, elevated = elevated, timeout = timeout)
  }
  if (!.has_smbclient()) {
    abort_netfs_backend_unavailable(
      "The installation command completed, but `smbclient` is still unavailable on PATH."
    )
  }
  invisible(TRUE)
}
