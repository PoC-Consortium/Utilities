## PoC1 to PoC2 conversion

```
 Usage:
    ./poc1to2.pl [options] <plotfile>

 Options:
    --help
      This help

    --mem <megabyte>
      Memory constraint to use less memory than the script would have used
      without any constraints (1/2000th of plot size)
      Given in megabyte, so -m 1000 will use roughly 1GB of memory

    --out <directory>
      Define a directory to write the converted plot file to. This switches
      to copy on write mode. (Else in-place is default) and allows you to
      fasten up the conversion at the expense of temporary additional HDD
      space.

    --quiet
      Quiet operation. Really quiet - no output at all (except failures).
      You can send the process into background and forget about it.
```

## PoC2 to PoC1 conversion

By specifying a PoC2 plot file instead of a PoC1 plot file, you could revert it back to PoC1.
This is not the intended mode of operation, but it works nevertheless.

It's possible, because PoC1 -> PoC2 conversion does not lose any
information, thus the conversion operation is symmetric. So should you - for whatever reasons - need to do this, here's how:


1. Rename your PoC2 plot file to contain a stagger info (ID\_START\_NONCES -> ID\_START\_NONCES\_STAGGER) where the STAGGER = NONCES
2. Let `poc1to2.pl` run on that file, so we *pretend* it's a PoC1 plot
3. We will get a ID\_START\_NONCES file, which we again rename to ID\_START\_NONCES\_STAGGER with NONCES = STAGGER, because in fact we now have an optimized PoC1 plot

Of course, you could now take that PoC1 file and again convert it into a PoC2 plot. Round you go.
