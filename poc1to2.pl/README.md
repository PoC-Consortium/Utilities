
## PoC1 to PoC2 conversion

This is not the intended mode of operation, but it works nevertheless.

It's possible, because PoC1 -> PoC2 conversion does not lose any
information, thus the conversion operation is symmetric. So should you - for whatever reasons - need to do this, here's how:


1. Rename your PoC2 plot file to contain a stagger info (ID\_START\_NONCES -> ID\_START\_NONCES\_STAGGER) where the STAGGER = NONCES
2. Let `poc1to2.pl` run on that file, so we *pretend* it's a PoC1 plot
3. We will get a ID\_START\_NONCES file, which we again rename to ID\_START\_NONCES\_STAGGER with NONCES = STAGGER, because in fact we now have an optimized PoC1 plot

Of course, you could now take that PoC1 file and again convert it into a PoC2 plot. Round you go.
