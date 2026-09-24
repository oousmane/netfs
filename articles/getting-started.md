# Getting started with netfs

``` r

library(netfs)
```

## Local filesystem operations

With no connection, netfs delegates directly to `fs`.

``` r

dir_ls(tempdir())
```

    ## /tmp/RtmpLOwPhh/file1c5e995fb5d
    ## /tmp/RtmpLOwPhh/rmarkdown-str1c5e78102fea.html

``` r

file_exists(tempdir())
```

    ## /tmp/RtmpLOwPhh 
    ##            TRUE

## Connection objects

Constructors validate configuration without opening a connection.
Passwords are stored through `keyring` and are not retained in
connection objects.

``` r

server <- ftp("ftp.example.org", user = "analyst")
set_creds(server)
```

Set `NETFS_KEYRING` in `.Renviron` to select a named keyring. Do not
store the password itself in `.Renviron`.

## SSH

``` r

server <- ssh("server.example.org", user = "user")
dir_ls("/data", con = server)
```

## FTP

``` r

server <- ftp("ftp.example.org", user = "user")
file_info("/data/input.csv", con = server)
```

## SMB

``` r

server <- smb("fileserver", "DATA", user = "user")
dir_ls("/2026", con = server)
```

## Uploading and downloading files

[`file_download()`](https://oousmane.github.io/netfs/reference/file_download.md)
copies from remote to local.
[`file_upload()`](https://oousmane.github.io/netfs/reference/file_upload.md)
copies in the other direction. Both protect existing destinations unless
`overwrite = TRUE`.

[`file_transfer()`](https://oousmane.github.io/netfs/reference/file_transfer.md)
copies between two remote connections through a temporary local staging
file. It preserves the source and removes the temporary file after
success or failure.

``` r

file_transfer(
  "/incoming/report.csv",
  "/archive/",
  from = ftp_server,
  to = smb_server
)
```

## Backend capabilities

``` r

netfs_capabilities()
```

    ## # A tibble: 6 × 4
    ##   backend available engine    package   
    ##   <chr>   <lgl>     <chr>     <chr>     
    ## 1 local   TRUE      libuv     fs        
    ## 2 ftp     TRUE      libcurl   curl      
    ## 3 ssh     TRUE      openssh   system    
    ## 4 smb     FALSE     smbclient smbclientr
    ## 5 webdav  TRUE      httr2     webdav    
    ## 6 s3      TRUE      paws      s3fs

## Error handling

Remote failures inherit from `netfs_error`; specific subclasses
distinguish authentication, missing paths, unavailable clients,
timeouts, and unsupported operations.
