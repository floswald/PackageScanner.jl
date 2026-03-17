* this julia package scans replication packages for the Journal of Political Economy for PII patterns
* we parse both code and data files. code scanning is trivial text analysis where we regex for patterns, data scanning is more involved because we need to be able to load many different file formats, which may be binary (or at any rate, not text based).
* This means we have an RCall.jl dependency because we use `haven` and `rio` packages. 
* each code addition needs to be covered by a specific unit test.
* all additions as incremental commits on a new branch, submitted via PR.
  