# Koivu Structural Blueprint - Bootstrapping Paths and Trust

Bootstrapping will start from a simple Lisp interpreter written in pure, generic LLVM IR. 
Koivu project will also keep (as part of its source code) target-dependent machine assembly files for popular platforms (x64, arm64 and possibly others) for seed lisp interpreter. 
Those target-dependant assemby files will be obtained by translating generic IR implementation of seed interpreter. At early stages of the project, we will use LLVM tools 
to translate LLVM IR to target assembly. Later, as Koivu project grows, this step will become self-hosted in a sense that we will use a Koivu tool (written in Scheme) for translation. 

The goal of portable Lisp interpreter seed implementation in generic IR is to simplify the maintanance of Koivu project. Target-specific assembly seeds will still have 
one important common property with generic IR seed: they all will be human-readable and human-inspectable, due to relatively small size. 

There will be two major paths for bootstrapping:

* Simple Path: bootstrap from assembly of seed interpreter on some consumer-grade operating system. 
* Secure Path: bootstrap from machine binary of seed interpreter in a secure bootstrapping environment, similar to GNU Bootstrapping Project. 

Simple Path is merely a convinience for majority of developers and users. As part of Simple Bootstrapping Path, Linux/MacOS users will have to translate 
the seed assembly code to an executable, using their platform assembler tool.
For Windows users Koivu may provide a binary executable seed of Lisp interpreter as part of Koivu download, again, just for convinience 
(since a bare Windows OS does not have an assembler tool). Please note that a small binary is still suitable to human inspection, at least in theory: 
you can open it in some text editor with hex display capability and verify that machine code corresponds to the assembly code. 
Of course, there are more practical ways to inspect the binary: scan it with antivirus, verify a digital signature, automatically compare it 
to the source assembly code using some custom automated tool etc. The smaller the binary, the easier it is to inspect. 

Simple Path is not truly secure/trustable. It is only as secure as the operating system where you build your compiler infrastructure. In practice, 
a particular instance of consumer-grade operating system may have various kinds of malicious code waiting to attack the compiler infrastructure: from random viruses to elaborate 
malicious code engineered by OS provider/seller. However, most people trust their OS provider/seller and use antivirus software to guard against viruses. 
So this bootstrapping path is good enough for majority of users. 

Secure Path is useful when full trust in compiler chain is an absolute requirement. (See Ken Thompson’s 1984 ACM Turing Award lecture, "Reflections on Trusting Trust.")
In that case, Koivu compiler infrastructure may serve as a drop-in replacement for the compiler seeding steps of GNU Bootstrapping Project. 
Or you may design an even more elaborate simultaneous OS and compiler bootstrapping procedure. Particular details of such a bootstrapping procedure 
are beyond the scope of Koivu project; Koivu's goal is to cover the compiler bootstrapping part only.
