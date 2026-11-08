# Koivu Platforms and Targets

**Status:** Architecture Blueprint  

**Component:** Global  

> Scarlet: Jack!<br>
> Jack: Scarlet!<br>
> (Scarlet promptly delivers a hard slap to Jack’s face and walks away angrily.)<br>
> Jack: I'm not sure I deserved that.<br>
> (Immediately, another woman named Giselle steps up to him.)<br>
> Giselle: Who was she?!<br>
> (Giselle slaps Jack hard across the opposite cheek and storms off.)<br>
> Jack: I may have deserved that.

Minimum OS platforms for Koivu project are 64-bit Windows, Linus and macOS. Initial set of target architectures are x86_64 and arm64. 

At some point in the future Koivu will support cross-compilation by a compiler running on a 64-bit operating system to popular 32-bit targets like arm32.
Please note that this is different from compiler itself running on a 32-bit OS.  

Support for bootstrapping and compilation on 32-bit architectures and corresponding operating systems is still under question. 
This may be possible as project matures if it does not complicate things too much. 

