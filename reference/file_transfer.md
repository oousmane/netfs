# Transfer a file between remote connections

`file_transfer()` moves data through a temporary local file. It does not
request a direct server-to-server transfer. The temporary file is
removed whether the transfer succeeds or fails. The source is never
deleted.

## Usage

``` r
file_transfer(path, new_path = basename(path), from, to, overwrite = FALSE)
```

## Arguments

- path:

  Source path inside `from`.

- new_path:

  Destination path inside `to`. If it identifies an existing directory
  or ends in `/`, the basename of `path` is appended.

- from:

  Source connection.

- to:

  Destination connection.

- overwrite:

  Replace an existing destination file.

## Value

The normalized remote destination path, invisibly, as an `fs_path`.

## See also

Other filesystem operations:
[`dir_copy()`](https://oousmane.github.io/netfs/reference/dir_copy.md),
[`dir_create()`](https://oousmane.github.io/netfs/reference/dir_create.md),
[`dir_delete()`](https://oousmane.github.io/netfs/reference/dir_delete.md),
[`dir_exists()`](https://oousmane.github.io/netfs/reference/dir_exists.md),
[`dir_info()`](https://oousmane.github.io/netfs/reference/dir_info.md),
[`dir_ls()`](https://oousmane.github.io/netfs/reference/dir_ls.md),
[`dir_map()`](https://oousmane.github.io/netfs/reference/dir_map.md),
[`dir_tree()`](https://oousmane.github.io/netfs/reference/dir_tree.md),
[`dir_walk()`](https://oousmane.github.io/netfs/reference/dir_walk.md),
[`file_access()`](https://oousmane.github.io/netfs/reference/file_access.md),
[`file_chmod()`](https://oousmane.github.io/netfs/reference/file_chmod.md),
[`file_chown()`](https://oousmane.github.io/netfs/reference/file_chown.md),
[`file_copy()`](https://oousmane.github.io/netfs/reference/file_copy.md),
[`file_create()`](https://oousmane.github.io/netfs/reference/file_create.md),
[`file_delete()`](https://oousmane.github.io/netfs/reference/file_delete.md),
[`file_download()`](https://oousmane.github.io/netfs/reference/file_download.md),
[`file_exists()`](https://oousmane.github.io/netfs/reference/file_exists.md),
[`file_info()`](https://oousmane.github.io/netfs/reference/file_info.md),
[`file_move()`](https://oousmane.github.io/netfs/reference/file_move.md),
[`file_show()`](https://oousmane.github.io/netfs/reference/file_show.md),
[`file_touch()`](https://oousmane.github.io/netfs/reference/file_touch.md),
[`file_upload()`](https://oousmane.github.io/netfs/reference/file_upload.md),
[`is_dir_empty()`](https://oousmane.github.io/netfs/reference/is_dir_empty.md),
[`is_file()`](https://oousmane.github.io/netfs/reference/is_file.md),
[`link_copy()`](https://oousmane.github.io/netfs/reference/link_copy.md),
[`link_create()`](https://oousmane.github.io/netfs/reference/link_create.md),
[`link_delete()`](https://oousmane.github.io/netfs/reference/link_delete.md),
[`link_path()`](https://oousmane.github.io/netfs/reference/link_path.md)

## Examples

``` r
if (FALSE) { # \dontrun{
ftp_server <- ftp("ftp.example.org", user = "analyst")
smb_server <- smb("fileserver", "DATA", user = "analyst")

file_transfer(
  path = "/incoming/report.csv",
  new_path = "/archive/",
  from = ftp_server,
  to = smb_server
)
} # }
```
