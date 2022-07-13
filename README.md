# ICE-V_Deepnote
Emulation of the Deep Note on an FPGA

## Abstract
The Lucas THX "Deep Note" audio logo is an iconic sound that most anyone who's
been to the movies since the late 1980s will recognize. It's been thoroughly
analyzed and meticulously recreated over the years in most synthesis media. One
of the better write ups about it is here:

https://earslap.com/article/recreating-the-thx-deep-note.html

I've used this analysis to build my own recreation in an FPGA, using hardware
sawtooth oscillators, a small RISC-V CPU and a very small amount of code to 
control the pitch and stereo pan. The 16-bit digital audio is converted to 
stereo analog with a simple PDM DAC. Here's an audio sample of what it sounds
like:

![Deepnote](docs/deepnote_0.mp4)

## Prerequisites

### FPGA
The design was prototyped on an ICE-V Wireless board which provides a Lattice
iCE40UP5k FPGA coupled to an Espressif ESP32C3 Mini module which controls the
FPGA configuration but is not involved in the synthesis in any way. Find out
more about the ICE-V Wireless board here:

https://groupgets.com/campaigns/1036-ice-v-wireless

Note that this code could easily be retargeted to any of the many UP5k
development boards that are on the market such as the Icebreaker, etc.

### PDM DAC
I used a custom home-made PDM filter / amp PMOD that I built for my own use,
but the general concept is very simple. The circuit here shows the core
components needed.

![Audio](docs/audio_filter.png)

### FPGA Toolchain
To synthesize the design for loading into the FPGA I used the OSS CAD Suite:

https://github.com/YosysHQ/oss-cad-suite-build

### RISC-V Toolchain
The soft RISC-V core in this design needs a C compiler. I used this one:

https://github.com/sifive/freedom-tools/releases

## Building
Assuming all the tools are available the entire project can be built with
the following commands:
```
cd Gateware/icestorm
make
make prog
```
Note that the Makefile assumes the location of the tools so you may need to
modifiy the paths to match your own installation locations.

