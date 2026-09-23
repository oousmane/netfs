.dir_ls <- function(con, path, ...) UseMethod(".dir_ls")
.dir_info <- function(con, path, ...) UseMethod(".dir_info")
.dir_info.default <- function(con, path, ...) {
  paths <- .dir_ls(con, path, ...)
  if (!length(paths)) return(.new_remote_info(character()))
  do.call(rbind, lapply(paths, function(p) .file_info(con, p)))
}
.dir_exists <- function(con, path, ...) UseMethod(".dir_exists")
.dir_create <- function(con, path, ...) UseMethod(".dir_create")
.dir_delete <- function(con, path, ...) UseMethod(".dir_delete")
.file_exists <- function(con, path, ...) UseMethod(".file_exists")
.file_delete <- function(con, path, ...) UseMethod(".file_delete")
.file_copy <- function(con, path, new_path, ...) UseMethod(".file_copy")
.file_move <- function(con, path, new_path, ...) UseMethod(".file_move")
.file_info <- function(con, path, ...) UseMethod(".file_info")
.file_download <- function(con, path, local, ...) UseMethod(".file_download")
.file_upload <- function(con, local, path, ...) UseMethod(".file_upload")

# Operations with no universal remote-protocol equivalent (POSIX
# permissions/ownership, arbitrary timestamps, symlinks). Each defaults to a
# clear "not supported by this backend" error, and only backends that can
# genuinely honor the operation (currently SSH, via the remote shell)
# override it - so an unsupported call fails predictably instead of one
# backend silently no-op'ing or a generic backend error leaking through.
.file_chmod <- function(con, path, mode, ...) UseMethod(".file_chmod")
.file_chmod.default <- function(con, path, mode, ...) .abort_netfs_op_unsupported(con, "file_chmod")

.file_chown <- function(con, path, user_id, group_id, ...) UseMethod(".file_chown")
.file_chown.default <- function(con, path, user_id, group_id, ...) .abort_netfs_op_unsupported(con, "file_chown")

.file_touch <- function(con, path, access_time, modification_time, ...) UseMethod(".file_touch")
.file_touch.default <- function(con, path, access_time, modification_time, ...) .abort_netfs_op_unsupported(con, "file_touch")

.file_access <- function(con, path, mode, ...) UseMethod(".file_access")
.file_access.default <- function(con, path, mode, ...) {
  .abort_netfs_op_unsupported(con, "file_access", sprintf("(mode: %s)", paste(mode, collapse = ", ")))
}

.link_create <- function(con, path, new_path, symbolic, ...) UseMethod(".link_create")
.link_create.default <- function(con, path, new_path, symbolic, ...) .abort_netfs_op_unsupported(con, "link_create")

.link_path <- function(con, path, ...) UseMethod(".link_path")
.link_path.default <- function(con, path, ...) .abort_netfs_op_unsupported(con, "link_path")

.link_delete <- function(con, path, ...) UseMethod(".link_delete")
.link_delete.default <- function(con, path, ...) .abort_netfs_op_unsupported(con, "link_delete")
