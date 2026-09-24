# Hidden credential display

Hidden credential display

## Usage

``` r
# S3 method for class 'netfs_creds'
print(x, ...)

# S3 method for class 'netfs_creds'
format(x, ...)

# S3 method for class 'netfs_creds'
str(object, ...)
```

## Arguments

- x, object:

  A credential object returned by
  [`get_creds()`](https://oousmane.github.io/netfs/reference/set_creds.md).

- ...:

  Unused.

## Value

[`print()`](https://rdrr.io/r/base/print.html) returns `x` invisibly,
[`format()`](https://rdrr.io/r/base/format.html) returns the hidden
marker, and [`str()`](https://rdrr.io/r/utils/str.html) returns `NULL`
invisibly.
