# Delete a symbolic link

Delete a symbolic link

## Usage

``` r
link_delete(path, con = NULL)
```

## Arguments

- path:

  A local or remote path. For
  [`dir_ls()`](https://oousmane.github.io/netfs/reference/dir_ls.md), a
  connection supplied as the first argument is shorthand for listing
  that connection's root.

- con:

  `NULL` for local `fs` behavior, or a netfs connection.

## Value

The path, invisibly, as an `fs_path`.

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
[`file_transfer()`](https://oousmane.github.io/netfs/reference/file_transfer.md),
[`file_upload()`](https://oousmane.github.io/netfs/reference/file_upload.md),
[`is_dir_empty()`](https://oousmane.github.io/netfs/reference/is_dir_empty.md),
[`is_file()`](https://oousmane.github.io/netfs/reference/is_file.md),
[`link_copy()`](https://oousmane.github.io/netfs/reference/link_copy.md),
[`link_create()`](https://oousmane.github.io/netfs/reference/link_create.md),
[`link_path()`](https://oousmane.github.io/netfs/reference/link_path.md)
