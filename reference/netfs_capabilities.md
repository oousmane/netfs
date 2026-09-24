# Report netfs backend capabilities

This function reports static client availability or operations supported
by a connection class. It never contacts a remote server.

## Usage

``` r
netfs_capabilities(con = NULL)
```

## Arguments

- con:

  Optional netfs connection.

## Value

With no connection, a tibble of `backend`, `available`, `engine` (the
underlying library or executable) and `package` (the R package providing
it, or `"system"` when there isn't one). With a connection, a tibble of
`operation` and `supported`.

## Examples

``` r
netfs_capabilities()
#> # A tibble: 6 × 4
#>   backend available engine    package   
#>   <chr>   <lgl>     <chr>     <chr>     
#> 1 local   TRUE      libuv     fs        
#> 2 ftp     TRUE      libcurl   curl      
#> 3 ssh     TRUE      openssh   system    
#> 4 smb     FALSE     smbclient smbclientr
#> 5 webdav  TRUE      httr2     webdav    
#> 6 s3      TRUE      paws      s3fs      
netfs_capabilities(ssh("server.example.org"))
#> # A tibble: 22 × 2
#>    operation   supported
#>    <chr>       <lgl>    
#>  1 dir_ls      TRUE     
#>  2 dir_info    TRUE     
#>  3 dir_exists  TRUE     
#>  4 dir_create  TRUE     
#>  5 dir_delete  TRUE     
#>  6 dir_copy    TRUE     
#>  7 file_exists TRUE     
#>  8 file_delete TRUE     
#>  9 file_copy   TRUE     
#> 10 file_move   TRUE     
#> # ℹ 12 more rows
```
