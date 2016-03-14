////////////////////////////////////////////////////////////////////////////////////
//  Example program that shows how to use levmar in order to fit the three-
//  parameter exponential model x_i = p[0]*exp(-p[1]*i) + p[2] to a set of
//  data measurements; example is based on a similar one from GSL.
//
//  Copyright (C) 2008  Manolis Lourakis (lourakis at ics forth gr)
//  Institute of Computer Science, Foundation for Research & Technology - Hellas
//  Heraklion, Crete, Greece.
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  Extracted section, modified from expfit.c in original levmar-2.5 distribution
//  by B. Hargreaves - simply to support a bi-exponential fit.  Random/main code removed.
////////////////////////////////////////////////////////////////////////////////////

#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#include "levmar.h"
#include "biexpfit.h"

#ifndef LM_SNGL_PREC
#error Example program assumes that levmar has been compiled with single precision, see LM_SNGL_PREC!
#endif



#ifdef _MSC_VER // MSVC
#include <process.h>
#define GETPID  _getpid
#elif defined(__GNUC__) // GCC
#include <sys/types.h>
#include <unistd.h>
#define GETPID  getpid
#else
#warning Do not know the name of the function returning the process id for your OS/compiler combination
#define GETPID  0
#endif /* _MSC_VER */



/* Bi-exponential model:  
	x_i = p[0]*((1-p[1])*exp(-p[2]*i) + p[1]*exp(-p[3]*i)) i=0...n-1 


 p[0] = S0 (signal for b=0)
 p[1] = Fp (perfusion fraction)
 p[2] = Dt (diffusion in tissue)
 p[3] = Dp (pseudodiffusion, due to microcirculation)
 
 data[i] contains b values.
*/

void biexpfunc(float *p, float *x, int m, int n, void *data)
{
register int i;
  for (i=0; i<n; i++) {
    x[i] = p[0]*((1-p[1])*exp(-p[2]* ((float *)data)[i] ) + p[1]*exp(-p[3]* ((float *)data)[i] ));
  }
}

/* Jacobian of biexpfunc() */
void jacbiexpfunc(float *p, float *jac, int m, int n, void *data)
{   
register int i, j;
float ep2i, ep3i, mp0i;

  
  /* fill Jacobian row by row */
  for(i=j=0; i<n; i++){
    ep2i=exp(-p[2]* ((float *)data)[i] ); 	/* intermediate calculation */
    ep3i=exp(-p[3]* ((float *)data)[i] ); 	/* intermediate calculation */
    mp0i=-p[0]* ((float *)data)[i];	/* intermediate calculation */

    jac[j++]= ((1-p[1])*ep2i + p[1]*ep3i);
    jac[j++]= p[0]*(ep3i - ep2i);
    jac[j++]= mp0i*(1-p[1])*ep2i;
    jac[j++]= mp0i*p[1]*ep3i;
  }
}




  /* optimization control parameters; passing to levmar NULL instead of opts reverts to defaults */
//  opts[0]=LM_INIT_MU; opts[1]=1E-15; opts[2]=1E-15; opts[3]=1E-20;
//  opts[4]=LM_DIFF_DELTA; // relevant only if the finite difference Jacobian version is used 

  /* invoke the optimization function */
//  ret=slevmar_der(biexpfunc, jacbiexpfunc, p, x, m, n, 1000, opts, info, NULL, NULL, NULL); // with analytic Jacobian
  //ret=dlevmar_dif(biexpfunc, p, x, m, n, 1000, opts, info, NULL, NULL, NULL); // without Jacobian

