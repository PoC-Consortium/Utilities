Dynamic Fee (Tx-Slots) Simulator

Usage:
       burst_dynfee_sim.pl <slots> [fee ]+

Meaning, your 1st argument is the number of slots and
all following arguments (space and/or comma separated list)
are the feet of the currently floating unconfirmed transactions.

Example:
       burst_dynfee_sim.pl 10 0.01,0.01,0.2,0.3 1 2 3 4


If you call it with that example, the output should look like this:

    $ burst_dynfee_sim.pl  10 0.01,0.01,0.2,0.3 1 2 3 4
    
        Fee Quantum: 0.00735
     Block Capacity: 10
    Fee slots:
      10: 0.0735
       9: 0.06615
       8: 0.0588
       7: 0.05145
       6: 0.0441
       5: 0.03675
       4: 0.0294
       3: 0.02205
       2: 0.0147
       1: 0.00735
    Pending Tx fees (descending-sorted and filtered too low):
    $VAR1 = [
              4,
              3,
              2,
              1,
              '0.3',
              '0.2',
              '0.01',
              '0.01'
            ];
    Distributing as follows:
    4 has slot @ 10 -> added
    3 has slot @ 9 -> added
    2 has slot @ 8 -> added
    1 has slot @ 7 -> added
    0.3 has slot @ 6 -> added
    0.2 has slot @ 5 -> added
    skipped slot @ 4 (0.01 too low for 0.0294).
    skipped slot @ 3 (0.01 too low for 0.02205).
    skipped slot @ 2 (0.01 too low for 0.0147).
    0.01 has slot @ 1 -> added
    Block capacity exhausted, leaving these for the next block:
    $VAR1 = [
              '0.01'
            ];
