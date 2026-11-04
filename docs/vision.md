Rationel behind Koivu compiler infrastructure

The goals of Koivu project are two-fold: compact, elegant and powerfull compiler hacking tools, 
and simple and secure bootstraping from a tiny amount of human-readable and human-inspectable machine assembly or binary code. 

Koivu project is planned to borrow heavily from LLVM and to be fully compatible with LLVM IR. 
The ultimate goal is to implement all of LLVM's IR tools (including IR lowering to target architectures), Clang and several compilers 
for popular program languages, including C++, Swift, Hylo, Rust and Jai. The minimum goal is to implement a full-fledged C compiler. 
Also Koivu plans to make its compilers fully compatible with Clang command-line tools, config tools and formats etc. 

The bootstrapping goal has mostly the same motivations as the GNU Bootstrapping Project: trust, reproducibility, security and resilence. 
In addition to this, having a compiler infrastructure easily bootable from small seed on all platforms is just very convinient for development community.
With all due respect, the GNU Bootstrapping Project in its current form has shortcomings: it is not easy to maintain bootstrappers for exotic platforms, 
and bootstrappint tools are cumbersome and motley (a mix of platform-specific machine assembly, antique C compilers and List interpreter at various stages).
Koivu tries to provide a cleaner, more compact and cross-platform bootstrapping path. 

Lisp is chosen as the main language for all levels of Koivu compiler infrastructure because it is the only programming language 
that meets both of Koivu's goals. Lisp is very powerfull high-level language with demonstrated ability for elegant code for parsers and code optimization passes. 
(One prominent example from the past is Chez Scheme with its native code generator and nano-passes design.) 
At the same time, Lisp is simple in its code. A basic Lisp interpreter is easy to implement in a small amount of human-readable machine assembly. 
Originally specified in 1958, Lisp is the second-oldest high-level programming language still in common use, after Fortran.
Frequently discussed shortcomings of Lisp are quite solvable. Slow execution speed should not be an issue for specialised Lisp AOT compiler with data-driven design 
and custom memory management strategies tailored for parsing and optimization passes. 


