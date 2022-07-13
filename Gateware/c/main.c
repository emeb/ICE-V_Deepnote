/*
 * main.c - top level of picorv32 firmware
 * 06-09-22 E. Brombaugh
 */

#include <stdio.h>
#include <string.h>
#include "system.h"
#include "acia.h"
#include "printf.h"
#include "clkcnt.h"

int32_t starts[32], ends[32];

const int16_t env[9] =
{
	0, 32, 64, 96,
	256, 512, 768, 1024,
	1024
};

/*
 * Where it all happens. All of it.
 */
void main()
{
	uint32_t i;
	
	/* uses stack */
	init_printf(0,acia_printf_putc);
	printf("\n\n\r-- ICE-V PolyOsc --\n\r");
		
	/* init all oscs w/ pan & 200-400 Hz */
	for(i=0;i<30;i++)
	{
		/* panning positions are random */
		int16_t pan = prn_reg & 0x7fff;
		sndgen_amp[i+0] = pan;
		sndgen_amp[i+1] = 32767-pan;
		
		/* starting frequencies in range 200-400Hz */
		/* note that pitch is 5736 lsb/Hz so this gives 1/10th Hz resolution */
		starts[i] = 573*(2000+(prn_reg & 2047));
		
		/* end frequencies are random over 6 octaves of MIDI note 14.5 */
		/* MIDI to freq = 440 * 2^((14.5-69)/12) = 18.89Hz */
		ends[i] = (573 * 189) << ((prn_reg % 7));
	}
	
	/* counting & flashing */
	uint32_t cnt = 0;
	int32_t fi, ii, m;
	int64_t tmp;
	printf("Looping...\n\r");
	while(1)
	{
		/* compute pitch envelope from piecewise linear table */
		fi = cnt & 0xff;
		ii = (cnt >> 8)&0x7;
		m = ((env[ii] * (0xff-fi)) + (env[ii+1] * fi))>>8;
		
		/* add noise to wiggle to pitch */
		for(i=0;i<30;i++)
		{
			/* random wander on start & end pitch */
			starts[i] += (prn_reg&8191)-4096;
			ends[i] += (prn_reg&31)-16;
			
			/* for testing just start and end */
			//sndgen_frq[i] = starts[i];
			//sndgen_frq[i] = ends[i];
			
			/* interpolate start to end */
			tmp = (m * (int64_t)ends[i]) + ((1024-m) * (int64_t)starts[i]);
			sndgen_frq[i] = tmp>>10;
		}
		
		/* Flash RGB throughout envelope */
		gp_out1 = ((cnt&1024)<<13) | ((cnt&512)<<6) | ((cnt&256)>>1);	
		cnt++;
		clkcnt_delayms(10);
	}
}
