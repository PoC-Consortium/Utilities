## PoC3 Prototype

This little tool provides (will provide) the basic PoC3 functionality:

1. create a synthetic/artificial PoC3 base plotfile (pre-individualization)
2. individualize an arbitrary (correctly padded) file into a PoC3 plot bound to a certain numericId
3. de-individualize PoC3 -> base file
4. perform mining on PoC3 (partially implemented/simulation only)

Currently individualization creates a new file. It should be possible
to make this operation also "in-file". The individualised PoC3 plot
file grows by 6.25% compared with the base file.

