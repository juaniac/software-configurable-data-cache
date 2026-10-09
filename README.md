# software-configurable-data-cache

For the courses CS-473 and CS-476 we are moving towards using a RISC-V soft-core. 
The core that is going to be used is the Hazard3 (https://github.com/wren6991/hazard3). This core does not provide any caches and performs single-word accesses using the AHB5 bus protocol. The goal of this project is to design in verilog a software-configurable data cache that connects to the core by using the AHB5 bus protocol and provides a Wishbone-bus interface (also allowing burst transfers by the Whishbone 2.0 specifications). The instruction cache should be software controllable by using the Special Purpose Register interface of the RISC-V (Zicsr-extention). 

The parameters to be configured are: 
- the size (1kB, 2kB, 4kB, and 8kB),
- the associativity (off, direct-mapped, 2-way-set-associative, 4-way-set-associative),
- the cache-line-size (16B, 32B, 64B, 128B),
- the replacements policy (round-robin, PLRU, LRU),
- the write policy (write-back, write-through)
